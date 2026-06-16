#include "native_window_agent.h"

#include <QWKCore/windowagentbase.h>
#include <QWKQuick/quickwindowagent.h>

#include <QtCore/QCoreApplication>
#include <QtCore/QDebug>
#include <QtCore/QDir>
#include <QtCore/QFileInfo>
#include <QtCore/QFileSystemWatcher>
#include <QtCore/QMargins>
#include <QtCore/QRectF>
#include <QtCore/QRegularExpression>
#include <QtCore/QSettings>
#include <QtCore/QString>
#include <QtCore/QVariant>
#include <QtCore/QtGlobal>
#include <QtGui/QCursor>
#include <QtGui/QScreen>
#include <QtGui/QWindow>
#include <QtGui/qguiapplication_platform.h>

#include <cmath>

#ifdef Q_OS_WIN
#    include <dwmapi.h>
#    include <windows.h>
#endif

#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
#    include <QtGui/QGuiApplication>
#    include <xcb/xcb.h>
#    include <X11/Xlib.h>
#    include <X11/Xatom.h>
#    include <X11/extensions/shape.h>
#endif

#ifdef Q_OS_WIN
static void terminateCurrentProcess() {
    TerminateProcess(GetCurrentProcess(), 0);
}

static bool windowPerfTraceEnabled() {
    return qEnvironmentVariableIsSet("QROUNDEDFRAME_WINDOW_PERF_TRACE");
}

static void traceWindowPerf(const wchar_t *message) {
    if (windowPerfTraceEnabled())
        OutputDebugStringW(message);
}

static int nativeCornerRadiusPx(int radius, HWND hwnd) {
    if (radius <= 0)
        return 0;
    UINT dpi = 96;
    if (hwnd) {
        if (auto getDpiForWindow = reinterpret_cast<UINT(WINAPI *)(HWND)>(
                GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForWindow"))) {
            dpi = getDpiForWindow(hwnd);
        }
    }
    const int scaledRadius = qMax(1, MulDiv(radius, int(dpi), 96));
    const int inwardBias = qBound(1, scaledRadius / 6, 3);
    return qMax(1, scaledRadius - inwardBias);
}

#endif

#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
static Display *sharedXDisplay() {
    static Display *display = nullptr;
    static bool initialized = false;
    if (!initialized) {
        initialized = true;
        display = XOpenDisplay(nullptr);
    }
    return display;
}

static bool canUseX11Shape() {
    Display *display = sharedXDisplay();
    if (!display)
        return false;
    int eventBase = 0;
    int errorBase = 0;
    return QGuiApplication::platformName().compare(QStringLiteral("xcb"), Qt::CaseInsensitive) == 0
           && XShapeQueryExtension(display, &eventBase, &errorBase);
}

static qreal normalizedDpr(qreal dpr) {
    return qMax<qreal>(1.0, dpr > 0.0 ? dpr : 1.0);
}

static int nativeCornerRadiusPx(int radius, qreal dpr) {
    if (radius <= 0)
        return 0;
    return qMax(1, int(std::lround(qreal(radius) * normalizedDpr(dpr))));
}

static int nativePx(int value, qreal dpr) {
    if (value <= 0)
        return 0;
    return qMax(1, int(std::lround(qreal(value) * normalizedDpr(dpr))));
}

static QSize nativeSizePx(const QSize &size, qreal dpr) {
    if (!size.isValid())
        return {};
    const qreal scale = normalizedDpr(dpr);
    return QSize(qMax(1, int(std::lround(qreal(size.width()) * scale))),
                 qMax(1, int(std::lround(qreal(size.height()) * scale))));
}

static QSize x11WindowSizePx(Display *display, Window window) {
    if (!display || !window)
        return {};
    XWindowAttributes attrs = {};
    if (XGetWindowAttributes(display, window, &attrs) && attrs.width > 0 && attrs.height > 0)
        return QSize(attrs.width, attrs.height);
    return {};
}

static bool dprTraceEnabled() {
    return qEnvironmentVariableIsSet("QROUNDEDFRAME_DPR_TRACE");
}

static qreal readXftDpiDpr(Display *display) {
    if (!display)
        return 0.0;
    char *resourceManager = XResourceManagerString(display);
    if (!resourceManager)
        return 0.0;
    const QString text = QString::fromLocal8Bit(resourceManager);
    const QRegularExpression re(QStringLiteral(R"(^\s*Xft\.dpi:\s*([0-9]+(?:\.[0-9]+)?))"),
                                QRegularExpression::MultilineOption);
    const QRegularExpressionMatch match = re.match(text);
    if (!match.hasMatch())
        return 0.0;
    bool ok = false;
    const qreal dpi = match.captured(1).toDouble(&ok);
    if (!ok || dpi <= 0.0)
        return 0.0;
    return qMax<qreal>(1.0, dpi / 96.0);
}

static qreal readKdeScaleFactorDpr() {
    const QString desktop = QStringList{
        QString::fromLocal8Bit(qgetenv("XDG_CURRENT_DESKTOP")),
        QString::fromLocal8Bit(qgetenv("XDG_SESSION_DESKTOP")),
        QString::fromLocal8Bit(qgetenv("DESKTOP_SESSION")),
    }.join(u';').toLower();
    if (!desktop.contains(QStringLiteral("kde")) && !desktop.contains(QStringLiteral("plasma")))
        return 0.0;
    const QString path = QDir::homePath() + QStringLiteral("/.config/kdeglobals");
    QSettings settings(path, QSettings::IniFormat);
    settings.beginGroup(QStringLiteral("KScreen"));
    const qreal scale = settings.value(QStringLiteral("ScaleFactor"), 0.0).toDouble();
    const QString screenScaleFactors = settings.value(QStringLiteral("ScreenScaleFactors")).toString();
    settings.endGroup();
    if (scale > 0.0)
        return qMax<qreal>(1.0, scale);
    const QStringList parts = screenScaleFactors.split(u';', Qt::SkipEmptyParts);
    for (const QString &part : parts) {
        const int equals = part.lastIndexOf(u'=');
        if (equals < 0)
            continue;
        bool ok = false;
        const qreal value = part.mid(equals + 1).toDouble(&ok);
        if (ok && value > 0.0)
            return qMax<qreal>(1.0, value);
    }
    return 0.0;
}

static XRectangle makeRect(short x, short y, unsigned short width, unsigned short height) {
    XRectangle rect = {};
    rect.x = x;
    rect.y = y;
    rect.width = width;
    rect.height = height;
    return rect;
}

static void setGtkFrameExtentsForWindow(QWindow *window, const QMargins &margins, qreal dpr) {
    Display *display = sharedXDisplay();
    if (!display || !window || QGuiApplication::platformName().compare(QStringLiteral("xcb"), Qt::CaseInsensitive) != 0)
        return;
    const Window xwindow = static_cast<Window>(window->winId());
    if (!xwindow)
        return;
    const Atom atom = XInternAtom(display, "_GTK_FRAME_EXTENTS", False);
    const long values[4] = {
        nativePx(margins.left(), dpr),
        nativePx(margins.right(), dpr),
        nativePx(margins.top(), dpr),
        nativePx(margins.bottom(), dpr),
    };
    XChangeProperty(display, xwindow, atom, XA_CARDINAL, 32, PropModeReplace,
                    reinterpret_cast<const unsigned char *>(values), 4);
    XFlush(display);
}

static QString linuxDesktopText()
{
    const QString desktop = QStringList{
        QString::fromLocal8Bit(qgetenv("XDG_CURRENT_DESKTOP")),
        QString::fromLocal8Bit(qgetenv("XDG_SESSION_DESKTOP")),
        QString::fromLocal8Bit(qgetenv("DESKTOP_SESSION")),
    }.join(u';').toLower();
    return desktop;
}

static bool desktopNeedsNormalWindowType()
{
    const QString desktop = linuxDesktopText();
    return desktop.contains(QStringLiteral("mate"))
        || desktop.contains(QStringLiteral("xfce"));
}

static void setX11NormalWindowTypeForDesktop(QWindow *window) {
    if (!desktopNeedsNormalWindowType() || !window)
        return;
    Display *display = sharedXDisplay();
    if (!display || QGuiApplication::platformName().compare(QStringLiteral("xcb"), Qt::CaseInsensitive) != 0)
        return;
    const Window xwindow = static_cast<Window>(window->winId());
    if (!xwindow)
        return;
    const Atom windowType = XInternAtom(display, "_NET_WM_WINDOW_TYPE", False);
    const Atom normal = XInternAtom(display, "_NET_WM_WINDOW_TYPE_NORMAL", False);
    XChangeProperty(display, xwindow, windowType, XA_ATOM, 32, PropModeReplace,
                    reinterpret_cast<const unsigned char *>(&normal), 1);
    XFlush(display);
}

static bool sendNetWmMoveResize(QWindow *window) {
    auto *x11Application = qGuiApp ? qGuiApp->nativeInterface<QNativeInterface::QX11Application>() : nullptr;
    Display *display = x11Application ? x11Application->display() : nullptr;
    if (!display || !window
        || QGuiApplication::platformName().compare(QStringLiteral("xcb"), Qt::CaseInsensitive) != 0) {
        return false;
    }

    const Window xwindow = static_cast<Window>(window->winId());
    if (!xwindow)
        return false;

    Window rootReturn = 0;
    Window childReturn = 0;
    int rootX = 0;
    int rootY = 0;
    int winX = 0;
    int winY = 0;
    unsigned int mask = 0;
    if (!XQueryPointer(display, DefaultRootWindow(display), &rootReturn, &childReturn,
                       &rootX, &rootY, &winX, &winY, &mask)) {
        return false;
    }

    XEvent event = {};
    event.xclient.type = ClientMessage;
    event.xclient.window = xwindow;
    event.xclient.message_type = XInternAtom(display, "_NET_WM_MOVERESIZE", False);
    event.xclient.format = 32;
    event.xclient.data.l[0] = rootX;
    event.xclient.data.l[1] = rootY;
    event.xclient.data.l[2] = 8; // _NET_WM_MOVERESIZE_MOVE
    event.xclient.data.l[3] = 1; // left mouse button
    event.xclient.data.l[4] = 1; // normal application source

    XUngrabPointer(display, CurrentTime);
    const int sent = XSendEvent(display, DefaultRootWindow(display), False,
                                SubstructureRedirectMask | SubstructureNotifyMask, &event);
    XFlush(display);
    return sent != 0;
}

static void releaseQtMouseGrab(QQuickWindow *window) {
    if (!window)
        return;
    if (QQuickItem *grabber = window->mouseGrabberItem())
        grabber->ungrabMouse();
}

static bool prefersEwmhSystemMove() {
    const QString desktop = linuxDesktopText();
    return desktop.contains(QStringLiteral("cinnamon"))
        || desktop.contains(QStringLiteral("mate"))
        || desktop.contains(QStringLiteral("xfce"))
        || desktop.contains(QStringLiteral("kde"))
        || desktop.contains(QStringLiteral("plasma"));
}

#endif

NativeWindowAgent::NativeWindowAgent(QObject *parent)
    : QWK::QuickWindowAgent(parent)
{
}

NativeWindowAgent::~NativeWindowAgent() {
    teardown();
}

void NativeWindowAgent::setup(QQuickWindow *window) {
    if (!window)
        return;
    if (m_window && m_window != window) {
        m_window->removeEventFilter(this);
        disconnect(m_window.data(), nullptr, this, nullptr);
    }
    m_window = window;
    m_window->installEventFilter(this);
    connect(m_window.data(), &QWindow::screenChanged, this, [this](QScreen *) {
        refreshScreenConnections();
        refreshNativeMetrics("window-screen-changed");
    });
    if (!m_clientSideShadowMode)
        QWK::QuickWindowAgent::setup(window);
    m_window->setColor(shellBackgroundColor());
#ifdef Q_OS_WIN
    m_hwnd = reinterpret_cast<void *>(m_window->winId());
#endif
    if (!m_clientSideShadowMode)
        QWK::QuickWindowAgent::setWindowAttribute(QStringLiteral("no-system-menu"), true);
    installNativeShellFilter();
    refreshScreenConnections();
    installX11RootPropertyListener();
    installKdeScaleWatcher();
    refreshNativeMetrics("setup");
}

void NativeWindowAgent::teardown() {
    uninstallNativeShellFilter();
    restoreClassBackgroundBrush();
    if (m_window)
        m_window->removeEventFilter(this);
    if (m_screen)
        disconnect(m_screen.data(), nullptr, this, nullptr);
    m_window.clear();
    m_screen.clear();
    m_titleBarItem.clear();
    m_minimizeButton.clear();
    m_maximizeButton.clear();
    m_closeButton.clear();
    m_lastRegionSize = QSize();
    m_lastRegionRadius = -1;
    m_inNativeSizeMove = false;
    m_linuxSystemMoveActive = false;
    m_x11RootPropertyListenerInstalled = false;
    if (m_kdeScaleWatcher) {
        if (auto *watcher = qobject_cast<QFileSystemWatcher *>(m_kdeScaleWatcher)) {
            const QStringList files = watcher->files();
            if (!files.isEmpty())
                watcher->removePaths(files);
            const QStringList directories = watcher->directories();
            if (!directories.isEmpty())
                watcher->removePaths(directories);
        }
    }
    m_kdeConfigDir.clear();
    m_kdeGlobalsPath.clear();
    m_kcmFontsPath.clear();
    m_lastNativeDpr = 0.0;
    m_x11ResourceDpr = 0.0;
    m_clientSideShadowMode = false;
#ifdef Q_OS_WIN
    m_hwnd = nullptr;
#endif
}

void NativeWindowAgent::setClientSideShadowMode(bool enabled) {
#ifdef Q_OS_LINUX
    m_clientSideShadowMode = enabled;
    applyWindowAttributes();
#else
    Q_UNUSED(enabled)
#endif
}

void NativeWindowAgent::setTitleBar(QQuickItem *item) {
    if (item) {
        m_titleBarItem = item;
        if (!m_clientSideShadowMode)
            QWK::QuickWindowAgent::setTitleBar(item);
    }
}

void NativeWindowAgent::setSystemButton(const QString &role, QQuickItem *item) {
    if (!item)
        return;
    if (m_clientSideShadowMode)
        return;
    const int button = systemButtonRole(role);
    if (button != QWK::WindowAgentBase::Unknown) {
        QWK::QuickWindowAgent::setSystemButton(
            static_cast<QWK::WindowAgentBase::SystemButton>(button), item);
        switch (button) {
        case QWK::WindowAgentBase::Minimize:
            m_minimizeButton = item;
            break;
        case QWK::WindowAgentBase::Maximize:
            m_maximizeButton = item;
            break;
        case QWK::WindowAgentBase::Close:
            m_closeButton = item;
            break;
        default:
            break;
        }
    }
}

void NativeWindowAgent::setHitTestVisible(QQuickItem *item, bool visible) {
    if (item && !m_clientSideShadowMode)
        QWK::QuickWindowAgent::setHitTestVisible(item, visible);
}

void NativeWindowAgent::setCustomShadowEnabled(bool enabled) {
    m_customShadow = enabled;
    applyWindowAttributes();
}

void NativeWindowAgent::setCornerRadius(int radius) {
    m_cornerRadius = qBound(0, radius, 96);
    applyWindowAttributes();
}

void NativeWindowAgent::setShadowAsset(const QUrl &source, int margin, qreal opacity) {
    m_shadowSource = source;
    m_shadowMargin = qBound(0, margin, 128);
    m_shadowOpacity = qBound<qreal>(0.0, opacity, 1.0);
    Q_UNUSED(m_shadowSource)
    Q_UNUSED(m_shadowMargin)
    Q_UNUSED(m_shadowOpacity)
}

void NativeWindowAgent::setShellBackgroundColor(const QColor &color) {
    if (!color.isValid())
        return;
    const QColor nextColor = color;
    if (m_shellBackgroundColor == nextColor)
        return;
    m_shellBackgroundColor = nextColor;
    if (m_window) {
        m_window->setColor(m_shellBackgroundColor);
#ifdef Q_OS_WIN
        HWND hwnd = reinterpret_cast<HWND>(m_hwnd);
        if (hwnd) {
            updateClassBackgroundBrush();
            InvalidateRect(hwnd, nullptr, FALSE);
        }
#endif
    }
}

void NativeWindowAgent::setResizeHitTestInsets(int edgeInset, int cornerInset) {
    const int edge = qBound(1, edgeInset, 64);
    const int corner = qBound(edge, cornerInset, 96);
    m_resizeEdgeInset = edge;
    m_resizeCornerInset = corner;
    if (!m_clientSideShadowMode) {
        setWindowAttribute(QStringLiteral("qrounded-resize-edge-inset"), edge);
        setWindowAttribute(QStringLiteral("qrounded-resize-corner-inset"), corner);
    }
}

void NativeWindowAgent::setGtkFrameExtents(int left, int top, int right, int bottom) {
    m_gtkFrameExtents = QMargins(qBound(0, left, 128),
                                 qBound(0, top, 128),
                                 qBound(0, right, 128),
                                 qBound(0, bottom, 128));
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    if (m_window)
        setGtkFrameExtentsForWindow(m_window, m_gtkFrameExtents, effectiveDevicePixelRatio());
#endif
}

qreal NativeWindowAgent::effectiveDevicePixelRatio() const {
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    if (m_x11ResourceDpr > 0.0)
        return m_x11ResourceDpr;
#endif
    return m_window ? qMax<qreal>(1.0, m_window->devicePixelRatio()) : 1.0;
}

void NativeWindowAgent::setFastExitOnClose(bool enabled) {
    m_fastExitOnClose = enabled;
}

bool NativeWindowAgent::isMaximized(QQuickWindow *window) const {
    QQuickWindow *target = window ? window : m_window.data();
    if (!target)
        return false;
#ifdef Q_OS_WIN
    HWND hwnd = reinterpret_cast<HWND>(target->winId());
    if (hwnd)
        return IsZoomed(hwnd);
#endif
    return target->visibility() == QWindow::Maximized || target->visibility() == QWindow::FullScreen;
}

bool NativeWindowAgent::nativeSizeMoveActive() const {
    return m_inNativeSizeMove;
}

void NativeWindowAgent::setNativeSizeMoveActive(bool active) {
    if (m_inNativeSizeMove == active)
        return;
    m_inNativeSizeMove = active;
    emit nativeSizeMoveActiveChanged();
}

void NativeWindowAgent::toggleMaximized(QQuickWindow *window) {
    QQuickWindow *target = window ? window : m_window.data();
    if (!target)
        return;

#ifdef Q_OS_WIN
    HWND hwnd = reinterpret_cast<HWND>(target->winId());
    if (hwnd) {
        const WPARAM command = IsZoomed(hwnd) ? SC_RESTORE : SC_MAXIMIZE;
        SendMessageW(hwnd, WM_SYSCOMMAND, command, 0);
        return;
    }
#endif

    if (target->visibility() == QWindow::Maximized || target->visibility() == QWindow::FullScreen)
        target->showNormal();
    else
        target->showMaximized();
}

bool NativeWindowAgent::startSystemMove(QQuickWindow *window) {
    QQuickWindow *target = window ? window : m_window.data();
    if (!target)
        return false;

#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    if (m_clientSideShadowMode) {
        if (prefersEwmhSystemMove() && sendNetWmMoveResize(target)) {
            releaseQtMouseGrab(target);
            m_linuxSystemMoveActive = true;
            return true;
        }
        if (target->startSystemMove())
            return true;
        if (sendNetWmMoveResize(target)) {
            releaseQtMouseGrab(target);
            m_linuxSystemMoveActive = true;
            return true;
        }
    }
#else
    Q_UNUSED(target)
#endif
    return false;
}

bool NativeWindowAgent::eventFilter(QObject *watched, QEvent *event) {
    if (watched == m_window.data() && event) {
        switch (event->type()) {
        case QEvent::Close:
            if (m_fastExitOnClose) {
#ifdef Q_OS_WIN
                terminateCurrentProcess();
#else
                QCoreApplication::exit(0);
#endif
                return true;
            }
            break;
        case QEvent::Show:
            applyWindowAttributes();
            break;
        case QEvent::WindowStateChange:
            applyWindowAttributes();
            break;
        case QEvent::DevicePixelRatioChange:
            traceNativeMetrics("event-dpr-change");
            applyWindowAttributes();
            break;
        case QEvent::Resize:
#ifdef Q_OS_WIN
            if (m_inNativeSizeMove) {
                fillWindowBackground();
            } else
#endif
            {
                if (m_clientSideShadowMode) {
                    clearWindowRegion();
                    applyClientSideShadowInputRegion();
                } else {
                    applyWindowRegion(false);
                }
            }
            break;
        default:
            break;
        }
    }
    return QObject::eventFilter(watched, event);
}

bool NativeWindowAgent::nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result) {
#ifdef Q_OS_WIN
    if (!m_window || !message)
        return false;
    if (eventType != QByteArrayLiteral("windows_generic_MSG")
        && eventType != QByteArrayLiteral("windows_dispatcher_MSG")) {
        return false;
    }

    MSG *msg = static_cast<MSG *>(message);
    HWND hwnd = reinterpret_cast<HWND>(m_hwnd);
    if (!hwnd || !msg->hwnd)
        return false;
    HWND targetRoot = GetAncestor(hwnd, GA_ROOT);
    HWND messageRoot = GetAncestor(msg->hwnd, GA_ROOT);
    if (msg->hwnd != hwnd && (!targetRoot || !messageRoot || targetRoot != messageRoot))
        return false;

    if (msg->message == WM_NCHITTEST) {
        const int hit = nativeSystemButtonHitTest(msg->lParam);
        if (hit != HTNOWHERE) {
            setNativeSystemButtonHover(hit);
            if (result)
                *result = hit;
            return true;
        }
        LRESULT dwmResult = 0;
        if (msg->hwnd == hwnd && DwmDefWindowProc(hwnd, msg->message, msg->wParam, msg->lParam, &dwmResult)) {
            if (dwmResult == HTREDUCE || dwmResult == HTZOOM || dwmResult == HTCLOSE) {
                setNativeSystemButtonHover(int(dwmResult));
                if (result)
                    *result = dwmResult;
                return true;
            }
        }
    }

    switch (msg->message) {
    case WM_NCLBUTTONDOWN: {
        const int hit = nativeSystemButtonHitTest(msg->lParam);
        if (msg->hwnd == hwnd && (hit == HTREDUCE || hit == HTZOOM || hit == HTCLOSE)) {
            setNativeSystemButtonHover(hit);
            m_pressedNativeButtonHit = hit;
            if (result)
                *result = 0;
            return true;
        }
        m_pressedNativeButtonHit = 0;
        break;
    }
    case WM_NCLBUTTONUP: {
        const int pressedHit = m_pressedNativeButtonHit;
        m_pressedNativeButtonHit = 0;
        if (msg->hwnd == hwnd && (pressedHit == HTREDUCE || pressedHit == HTZOOM || pressedHit == HTCLOSE)) {
            const int releaseHit = nativeSystemButtonHitTest(msg->lParam);
            if (releaseHit == pressedHit) {
                if (pressedHit == HTREDUCE) {
                    ShowWindow(hwnd, SW_MINIMIZE);
                } else if (pressedHit == HTZOOM) {
                    const WPARAM command = IsZoomed(hwnd) ? SC_RESTORE : SC_MAXIMIZE;
                    SendMessageW(hwnd, WM_SYSCOMMAND, command, 0);
                } else if (pressedHit == HTCLOSE) {
                    SendMessageW(hwnd, WM_SYSCOMMAND, SC_CLOSE, 0);
                }
            }
            if (result)
                *result = 0;
            return true;
        }
        break;
    }
    case WM_LBUTTONUP:
    case WM_CANCELMODE:
    case WM_CAPTURECHANGED:
        m_pressedNativeButtonHit = 0;
        break;
    case WM_MOUSEMOVE:
        setNativeSystemButtonHover(HTNOWHERE);
        break;
    case WM_NCMOUSEMOVE:
    case WM_NCMOUSELEAVE: {
        if (msg->message == WM_NCMOUSELEAVE)
            setNativeSystemButtonHover(HTNOWHERE);
        LRESULT dwmResult = 0;
        if (msg->hwnd == hwnd && DwmDefWindowProc(hwnd, msg->message, msg->wParam, msg->lParam, &dwmResult)) {
            if (result)
                *result = dwmResult;
            return true;
        }
        const int hitCode = int(msg->wParam & 0xFFFF);
        if (msg->hwnd == hwnd && (hitCode == HTREDUCE || hitCode == HTZOOM || hitCode == HTCLOSE)
            && nativeSystemButtonHitTest(msg->lParam) == hitCode) {
            setNativeSystemButtonHover(hitCode);
            if (result)
                *result = DefWindowProcW(hwnd, msg->message, msg->wParam, msg->lParam);
            return true;
        }
        break;
    }
    case WM_NCCALCSIZE:
        if (m_customShadow && msg->hwnd == hwnd && msg->wParam) {
            // 自定义圆角 + Qt Quick live resize 时，新增客户区如果不让 Windows 失效重绘，
            // 快速放大窗口会短暂露出默认黑底。这里交给系统正常重绘，不用 timer 催 QML。
            if (result)
                *result = WVR_REDRAW;
            return true;
        }
        return false;
    case WM_CLOSE:
        if (m_fastExitOnClose) {
            if (result)
                *result = 0;
            terminateCurrentProcess();
            return true;
        }
        return false;
    case WM_SYSCOMMAND:
        if (m_fastExitOnClose && ((msg->wParam & 0xFFF0) == SC_CLOSE)) {
            if (result)
                *result = 0;
            terminateCurrentProcess();
            return true;
        }
        return false;
    case WM_ERASEBKGND: {
        if (msg->hwnd != hwnd)
            return false;
        HDC hdc = reinterpret_cast<HDC>(msg->wParam);
        if (!hdc)
            return false;
        RECT rect = {};
        if (!GetClientRect(hwnd, &rect))
            return false;
        const QColor color = shellBackgroundColor();
        HBRUSH brush = CreateSolidBrush(RGB(color.red(), color.green(), color.blue()));
        if (!brush)
            return false;
        FillRect(hdc, &rect, brush);
        DeleteObject(brush);
        if (result)
            *result = 1;
        return true;
    }
    case WM_ENTERSIZEMOVE:
        traceWindowPerf(L"QRoundedFrame: WM_ENTERSIZEMOVE\n");
        setNativeSizeMoveActive(true);
        // 缩放过程中保持圆角 region。之前清掉 region 会让拖拽中变直角，
        // 也更容易在左上角缩放时露出底层窗口。
        applyWindowRegion(false);
        fillWindowBackground();
        return false;
    case WM_SIZING: {
        fillWindowBackground();
        if (msg->lParam) {
            const RECT *rect = reinterpret_cast<const RECT *>(msg->lParam);
            const int targetWidth = rect->right - rect->left;
            const int targetHeight = rect->bottom - rect->top;
            // 使用 Win32 目标尺寸提前更新 region，避免等 Qt 下一帧 Resize 后才修圆角。
            if (m_customShadow)
                applyWindowRegionForNativeSize(targetWidth, targetHeight, false);
        }
        return false;
    }
    case WM_WINDOWPOSCHANGING: {
        WINDOWPOS *pos = reinterpret_cast<WINDOWPOS *>(msg->lParam);
        const bool sizeChanged = pos && !(pos->flags & SWP_NOSIZE) && pos->cx > 0 && pos->cy > 0;
        if (sizeChanged) {
            fillWindowBackground();
            // 最大化/还原/贴边也会先到 WINDOWPOSCHANGING；和 WM_SIZING 走同一条 region 路线。
            if (m_customShadow)
                applyWindowRegionForNativeSize(pos->cx, pos->cy, false);
            traceWindowPerf(L"QRoundedFrame: WM_WINDOWPOSCHANGING size\n");
        } else {
            traceWindowPerf(L"QRoundedFrame: WM_WINDOWPOSCHANGING move-only\n");
        }
        return false;
    }
    case WM_SIZE:
        fillWindowBackground();
        return false;
    case WM_WINDOWPOSCHANGED: {
        WINDOWPOS *pos = reinterpret_cast<WINDOWPOS *>(msg->lParam);
        const bool sizeChanged = pos && !(pos->flags & SWP_NOSIZE) && pos->cx > 0 && pos->cy > 0;
        if (sizeChanged) {
            fillWindowBackground();
            traceWindowPerf(L"QRoundedFrame: WM_WINDOWPOSCHANGED size\n");
        } else {
            traceWindowPerf(L"QRoundedFrame: WM_WINDOWPOSCHANGED move-only\n");
        }
        return false;
    }
    case WM_EXITSIZEMOVE:
        traceWindowPerf(L"QRoundedFrame: WM_EXITSIZEMOVE\n");
        setNativeSizeMoveActive(false);
        applyWindowRegion(false);
        fillWindowBackground();
        m_window->requestUpdate();
        return false;
    default:
        break;
    }
#else
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    if (!m_window || !message)
        return false;
    if (eventType != QByteArrayLiteral("xcb_generic_event_t"))
        return false;
    auto *event = static_cast<xcb_generic_event_t *>(message);
    const uint8_t responseType = event->response_type & ~0x80;
    if (responseType == XCB_PROPERTY_NOTIFY) {
        auto *propertyEvent = reinterpret_cast<xcb_property_notify_event_t *>(event);
        Display *display = sharedXDisplay();
        if (display && propertyEvent->window == DefaultRootWindow(display)) {
            const Atom resourceManager = XInternAtom(display, "RESOURCE_MANAGER", False);
            const Atom xsettings = XInternAtom(display, "_XSETTINGS_SETTINGS", False);
            const Atom qtSettings = XInternAtom(display, "_QT_SETTINGS_TIMESTAMP_:0", False);
            if (propertyEvent->atom == resourceManager || propertyEvent->atom == xsettings || propertyEvent->atom == qtSettings) {
                if (dprTraceEnabled())
                    qInfo() << "QRoundedFrame DPR root-property"
                            << (propertyEvent->atom == resourceManager ? "RESOURCE_MANAGER"
                                : propertyEvent->atom == xsettings ? "_XSETTINGS_SETTINGS"
                                                                    : "_QT_SETTINGS_TIMESTAMP_:0");
                refreshNativeMetrics("x11-root-property");
            }
        }
        return false;
    }
    if (!m_linuxSystemMoveActive)
        return false;
    switch (responseType) {
    case XCB_BUTTON_RELEASE:
    case XCB_FOCUS_OUT:
    case XCB_LEAVE_NOTIFY:
    case XCB_UNMAP_NOTIFY:
        m_linuxSystemMoveActive = false;
        emit nativeSystemMoveFinished();
        break;
    default:
        break;
    }
#else
    Q_UNUSED(eventType)
    Q_UNUSED(message)
    Q_UNUSED(result)
#endif
#endif
    return false;
}

int NativeWindowAgent::systemButtonRole(const QString &role) {
    const QString key = role.trimmed().toLower();
    if (key == QStringLiteral("icon") || key == QStringLiteral("windowicon"))
        return QWK::WindowAgentBase::WindowIcon;
    if (key == QStringLiteral("help"))
        return QWK::WindowAgentBase::Help;
    if (key == QStringLiteral("minimize") || key == QStringLiteral("min"))
        return QWK::WindowAgentBase::Minimize;
    if (key == QStringLiteral("maximize") || key == QStringLiteral("max") || key == QStringLiteral("restore"))
        return QWK::WindowAgentBase::Maximize;
    if (key == QStringLiteral("close"))
        return QWK::WindowAgentBase::Close;
    return QWK::WindowAgentBase::Unknown;
}

QColor NativeWindowAgent::shellBackgroundColor() const {
    if (m_shellBackgroundColor.isValid())
        return m_shellBackgroundColor;
    return QColor(16, 18, 24);
}

void NativeWindowAgent::applyWindowAttributes() {
    if (!m_window)
        return;
    m_window->setColor(shellBackgroundColor());

#ifdef Q_OS_WIN
    HWND hwnd = reinterpret_cast<HWND>(m_hwnd);
    if (!hwnd)
        return;
    updateClassBackgroundBrush();
    if (!m_customShadow) {
        const DWORD renderingPolicy = 0; // DWMNCRP_USEWINDOWSTYLE
        DwmSetWindowAttribute(hwnd, 2, &renderingPolicy, sizeof(renderingPolicy));
        const DWORD cornerPref = 2; // DWMWCP_ROUND
        DwmSetWindowAttribute(hwnd, 33, &cornerPref, sizeof(cornerPref));
        const COLORREF borderNone = 0xFFFFFFFE;
        DwmSetWindowAttribute(hwnd, 34, &borderNone, sizeof(borderNone));
        clearWindowRegion();
        return;
    }
    // Keep DWM non-client rendering enabled. Disabling it lets Win10 draw
    // classic frame/caption pixels behind the transparent QML chrome, which can
    // leak around rounded corners during live resize after maximize/restore.
    const DWORD ncPolicy = 2; // DWMNCRP_ENABLED
    DwmSetWindowAttribute(hwnd, 2, &ncPolicy, sizeof(ncPolicy));

    const QMargins frameMargins(0, 0, 0, 0);
    setWindowAttribute(QStringLiteral("extra-margins"),
                       QVariant::fromValue(frameMargins));
    const MARGINS margins = {frameMargins.left(), frameMargins.right(),
                             frameMargins.top(), frameMargins.bottom()};
    DwmExtendFrameIntoClientArea(hwnd, &margins);

    const DWORD doNotRound = 1; // DWMWCP_DONOTROUND
    DwmSetWindowAttribute(hwnd, 33, &doNotRound, sizeof(doNotRound));
    const COLORREF borderNone = 0xFFFFFFFE;
    DwmSetWindowAttribute(hwnd, 34, &borderNone, sizeof(borderNone));
    DwmSetWindowAttribute(hwnd, 35, &borderNone, sizeof(borderNone));

    // Keep visual clipping in this integration layer. QWindowKit owns native
    // hit-testing and window behavior; this project owns the custom rounded shell.
    applyWindowRegion(false);
#else
    setGtkFrameExtentsForWindow(m_window, m_gtkFrameExtents, effectiveDevicePixelRatio());
    if (m_clientSideShadowMode) {
        setX11NormalWindowTypeForDesktop(m_window);
        clearWindowRegion();
        applyClientSideShadowInputRegion();
    } else if (m_customShadow) {
        applyWindowRegion(false);
    } else {
        clearWindowRegion();
    }
#endif
}

void NativeWindowAgent::applyWindowRegion(bool redraw) {
#ifdef Q_OS_WIN
    if (!m_window)
        return;
    HWND hwnd = reinterpret_cast<HWND>(m_hwnd);
    if (!hwnd)
        return;

    if (!m_customShadow) {
        clearWindowRegion();
        return;
    }

    RECT windowRect = {};
    if (!GetWindowRect(hwnd, &windowRect))
        return;
    const int width = windowRect.right - windowRect.left;
    const int height = windowRect.bottom - windowRect.top;
    if (width <= 0 || height <= 0) {
        clearWindowRegion();
        return;
    }

    applyWindowRegionForNativeSize(width, height, redraw);
#else
    if (!m_window)
        return;
    const QSize size = nativeSizePx(m_window->size(), effectiveDevicePixelRatio());
    applyWindowRegionForNativeSize(size.width(), size.height(), redraw);
#endif
}

void NativeWindowAgent::applyClientSideShadowInputRegion() {
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    if (!m_window)
        return;
    Display *display = sharedXDisplay();
    if (!canUseX11Shape() || !display)
        return;
    const Window windowId = static_cast<Window>(m_window->winId());
    if (!windowId)
        return;

    QSize size = x11WindowSizePx(display, windowId);
    if (!size.isValid())
        size = nativeSizePx(m_window->size(), effectiveDevicePixelRatio());

    const qreal dpr = effectiveDevicePixelRatio();
    const int left = qBound(0, nativePx(m_gtkFrameExtents.left(), dpr), size.width());
    const int top = qBound(0, nativePx(m_gtkFrameExtents.top(), dpr), size.height());
    const int right = qBound(0, nativePx(m_gtkFrameExtents.right(), dpr), qMax(0, size.width() - left));
    const int bottom = qBound(0, nativePx(m_gtkFrameExtents.bottom(), dpr), qMax(0, size.height() - top));
    const int contentWidth = qMax(0, size.width() - left - right);
    const int contentHeight = qMax(0, size.height() - top - bottom);
    const int edgeGrip = m_clientSideShadowMode ? nativePx(m_resizeEdgeInset, dpr) : 0;
    const int inputLeft = qMax(0, left - edgeGrip);
    const int inputTop = qMax(0, top - edgeGrip);
    const int inputRight = qMin(size.width(), left + contentWidth + edgeGrip);
    const int inputBottom = qMin(size.height(), top + contentHeight + edgeGrip);
    const int inputWidth = qMax(0, inputRight - inputLeft);
    const int inputHeight = qMax(0, inputBottom - inputTop);
    if (dprTraceEnabled()) {
        qInfo() << "QRoundedFrame DPR shape-input"
                << "dpr" << dpr
                << "windowSize" << m_window->size()
                << "x11Size" << size
                << "rect" << QRect(inputLeft, inputTop, inputWidth, inputHeight)
                << "extents" << m_gtkFrameExtents;
    }
    if (inputWidth <= 0 || inputHeight <= 0) {
        XShapeCombineMask(display, windowId, ShapeInput, 0, 0, None, ShapeSet);
        XFlush(display);
        return;
    }

    XRectangle rect = makeRect(short(inputLeft), short(inputTop), unsigned(inputWidth), unsigned(inputHeight));
    XShapeCombineRectangles(display, windowId, ShapeInput, 0, 0, &rect, 1, ShapeSet, YXBanded);
    XFlush(display);
#endif
}

void NativeWindowAgent::applyWindowRegionForNativeSize(int width, int height, bool redraw) {
#ifdef Q_OS_WIN
    if (!m_window)
        return;
    HWND hwnd = reinterpret_cast<HWND>(m_hwnd);
    if (!hwnd)
        return;
    if (width <= 0 || height <= 0)
        return;

    const bool square = m_cornerRadius <= 0
                        || m_window->visibility() == QWindow::Maximized
                        || m_window->visibility() == QWindow::FullScreen
                        || IsZoomed(hwnd);
    const int radius = square ? 0 : nativeCornerRadiusPx(m_cornerRadius, hwnd);
    const QSize size(width, height);
    if (m_lastRegionSize == size && m_lastRegionRadius == radius)
        return;

    HRGN region = square
                      ? CreateRectRgn(0, 0, width + 1, height + 1)
                      : CreateRoundRectRgn(0, 0, width + 1, height + 1, radius * 2, radius * 2);
    if (!region)
        return;
    const BOOL redrawRegion = redraw ? TRUE : FALSE;
    if (SetWindowRgn(hwnd, region, redrawRegion)) {
        m_lastRegionSize = size;
        m_lastRegionRadius = radius;
        return;
    }
    DeleteObject(region);
#else
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    Q_UNUSED(redraw)
    if (!m_window || width <= 0 || height <= 0)
        return;
    Display *display = sharedXDisplay();
    if (!canUseX11Shape() || !display)
        return;

    const Window windowId = static_cast<Window>(m_window->winId());
    if (!windowId)
        return;
    const QSize nativeWindowSize = x11WindowSizePx(display, windowId);
    if (nativeWindowSize.isValid()) {
        width = nativeWindowSize.width();
        height = nativeWindowSize.height();
    }

    const bool square = m_cornerRadius <= 0
                        || m_window->visibility() == QWindow::Maximized
                        || m_window->visibility() == QWindow::FullScreen;
    const int radius = square ? 0 : qMin(nativeCornerRadiusPx(m_cornerRadius, effectiveDevicePixelRatio()), qMin(width, height) / 2);
    const QSize size(width, height);
    if (m_lastRegionSize == size && m_lastRegionRadius == radius)
        return;

    if (square || radius <= 0) {
        XShapeCombineMask(display, windowId, ShapeBounding, 0, 0, None, ShapeSet);
        XFlush(display);
        m_lastRegionSize = size;
        m_lastRegionRadius = radius;
        return;
    }

    QVector<XRectangle> rects;
    rects.reserve(qMax(1, height));
    for (int y = 0; y < height; ++y) {
        int inset = 0;
        if (y < radius) {
            const double dy = double(radius - y - 0.5);
            inset = qMax(0, int(std::ceil(radius - std::sqrt(qMax(0.0, double(radius * radius) - dy * dy)))));
        } else if (y >= height - radius) {
            const double dy = double(y - (height - radius) + 0.5);
            inset = qMax(0, int(std::ceil(radius - std::sqrt(qMax(0.0, double(radius * radius) - dy * dy)))));
        }
        const int x = qMin(inset, width / 2);
        const int rowWidth = qMax(0, width - x * 2);
        if (rowWidth > 0)
            rects.append(makeRect(short(x), short(y), unsigned(rowWidth), 1));
    }
    if (rects.isEmpty())
        return;

    XShapeCombineRectangles(display, windowId, ShapeBounding, 0, 0,
                            rects.data(), rects.size(), ShapeSet, YXBanded);
    XFlush(display);
    m_lastRegionSize = size;
    m_lastRegionRadius = radius;
#else
    Q_UNUSED(redraw)
#endif
#endif
}

void NativeWindowAgent::fillWindowBackground() {
#ifdef Q_OS_WIN
    if (!m_window)
        return;
    HWND hwnd = reinterpret_cast<HWND>(m_hwnd);
    if (!hwnd)
        return;
    RECT rect = {};
    if (!GetClientRect(hwnd, &rect))
        return;
    HDC hdc = GetDC(hwnd);
    if (!hdc)
        return;
    const QColor color = shellBackgroundColor();
    HBRUSH brush = CreateSolidBrush(RGB(color.red(), color.green(), color.blue()));
    if (brush) {
        FillRect(hdc, &rect, brush);
        DeleteObject(brush);
    }
    ReleaseDC(hwnd, hdc);
#endif
}

void NativeWindowAgent::installNativeShellFilter() {
#if defined(Q_OS_WIN) || (defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE))
    if (m_nativeShellFilterInstalled || !qApp)
        return;
    qApp->installNativeEventFilter(this);
    m_nativeShellFilterInstalled = true;
#endif
}

void NativeWindowAgent::uninstallNativeShellFilter() {
#if defined(Q_OS_WIN) || (defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE))
    if (!m_nativeShellFilterInstalled || !qApp)
        return;
    qApp->removeNativeEventFilter(this);
    m_nativeShellFilterInstalled = false;
#endif
}

void NativeWindowAgent::updateClassBackgroundBrush() {
#ifdef Q_OS_WIN
    HWND hwnd = reinterpret_cast<HWND>(m_hwnd);
    if (!hwnd)
        return;

    const QColor color = shellBackgroundColor();
    HBRUSH nextBrush = CreateSolidBrush(RGB(color.red(), color.green(), color.blue()));
    if (!nextBrush)
        return;

    const LONG_PTR previous = SetClassLongPtrW(hwnd, GCLP_HBRBACKGROUND, reinterpret_cast<LONG_PTR>(nextBrush));
    if (!m_previousClassBackgroundBrush && previous)
        m_previousClassBackgroundBrush = static_cast<quintptr>(previous);
    HBRUSH oldBrush = reinterpret_cast<HBRUSH>(m_backgroundBrush);
    m_backgroundBrush = reinterpret_cast<quintptr>(nextBrush);
    if (oldBrush)
        DeleteObject(oldBrush);
#endif
}

void NativeWindowAgent::restoreClassBackgroundBrush() {
#ifdef Q_OS_WIN
    if (m_hwnd) {
        HWND hwnd = reinterpret_cast<HWND>(m_hwnd);
        if (hwnd && m_previousClassBackgroundBrush) {
            SetClassLongPtrW(hwnd, GCLP_HBRBACKGROUND,
                             static_cast<LONG_PTR>(m_previousClassBackgroundBrush));
        }
    }
    HBRUSH brush = reinterpret_cast<HBRUSH>(m_backgroundBrush);
    if (brush)
        DeleteObject(brush);
    m_backgroundBrush = 0;
    m_previousClassBackgroundBrush = 0;
#endif
}

void NativeWindowAgent::refreshScreenConnections() {
    QScreen *screen = m_window ? m_window->screen() : nullptr;
    if (m_screen == screen)
        return;
    if (m_screen)
        disconnect(m_screen.data(), nullptr, this, nullptr);
    m_screen = screen;
    if (!m_screen)
        return;

    const auto refresh = [this]() {
        refreshNativeMetrics("screen-signal");
    };
    connect(m_screen.data(), &QScreen::geometryChanged, this, refresh);
    connect(m_screen.data(), &QScreen::availableGeometryChanged, this, refresh);
    connect(m_screen.data(), &QScreen::physicalSizeChanged, this, refresh);
    connect(m_screen.data(), &QScreen::logicalDotsPerInchChanged, this, refresh);
    connect(m_screen.data(), &QScreen::physicalDotsPerInchChanged, this, refresh);
    connect(m_screen.data(), &QScreen::virtualGeometryChanged, this, refresh);
}

void NativeWindowAgent::refreshNativeMetrics(const char *reason) {
    const qreal previousDpr = effectiveDevicePixelRatio();
    Display *display = sharedXDisplay();
    if (auto *x11Application = qGuiApp ? qGuiApp->nativeInterface<QNativeInterface::QX11Application>() : nullptr)
        display = x11Application->display();
    m_x11ResourceDpr = readKdeScaleFactorDpr();
    if (m_x11ResourceDpr <= 0.0)
        m_x11ResourceDpr = readXftDpiDpr(display);
    m_lastNativeDpr = effectiveDevicePixelRatio();
    if (!qFuzzyCompare(previousDpr, m_lastNativeDpr))
        emit effectiveDevicePixelRatioChanged();
    traceNativeMetrics(reason);
    applyWindowAttributes();
}

void NativeWindowAgent::traceNativeMetrics(const char *reason) const {
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    if (!dprTraceEnabled())
        return;
    Display *display = sharedXDisplay();
    const Window windowId = m_window ? static_cast<Window>(m_window->winId()) : 0;
    const QSize x11Size = x11WindowSizePx(display, windowId);
    QScreen *screen = m_window ? m_window->screen() : nullptr;
    qInfo() << "QRoundedFrame DPR"
            << reason
            << "windowDpr" << (m_window ? m_window->devicePixelRatio() : 0.0)
            << "screenDpr" << (screen ? screen->devicePixelRatio() : 0.0)
            << "resourceDpr" << m_x11ResourceDpr
            << "effectiveDpr" << effectiveDevicePixelRatio()
            << "logicalDpi" << (screen ? screen->logicalDotsPerInch() : 0.0)
            << "qtSize" << (m_window ? m_window->size() : QSize())
            << "x11Size" << x11Size
            << "extents" << m_gtkFrameExtents;
#else
    Q_UNUSED(reason)
#endif
}

void NativeWindowAgent::installX11RootPropertyListener() {
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    if (m_x11RootPropertyListenerInstalled)
        return;
    auto *x11Application = qGuiApp ? qGuiApp->nativeInterface<QNativeInterface::QX11Application>() : nullptr;
    Display *display = x11Application ? x11Application->display() : nullptr;
    if (!display || QGuiApplication::platformName().compare(QStringLiteral("xcb"), Qt::CaseInsensitive) != 0)
        return;
    XSelectInput(display, DefaultRootWindow(display), PropertyChangeMask);
    XFlush(display);
    m_x11RootPropertyListenerInstalled = true;
    if (dprTraceEnabled())
        qInfo() << "QRoundedFrame DPR root-listener installed";
#endif
}

void NativeWindowAgent::installKdeScaleWatcher() {
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    if (QGuiApplication::platformName().compare(QStringLiteral("xcb"), Qt::CaseInsensitive) != 0)
        return;
    const QString desktop = linuxDesktopText();
    if (!desktop.contains(QStringLiteral("kde")) && !desktop.contains(QStringLiteral("plasma")))
        return;

    auto *watcher = qobject_cast<QFileSystemWatcher *>(m_kdeScaleWatcher);
    if (!watcher) {
        watcher = new QFileSystemWatcher(this);
        m_kdeScaleWatcher = watcher;
        connect(watcher, &QFileSystemWatcher::fileChanged, this, [this](const QString &) {
            refreshKdeScaleWatcherPaths();
            refreshNativeMetrics("kde-scale-file");
        });
        connect(watcher, &QFileSystemWatcher::directoryChanged, this, [this](const QString &) {
            refreshKdeScaleWatcherPaths();
            refreshNativeMetrics("kde-scale-dir");
        });
    }
    refreshKdeScaleWatcherPaths();
#endif
}

void NativeWindowAgent::refreshKdeScaleWatcherPaths() {
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    auto *watcher = qobject_cast<QFileSystemWatcher *>(m_kdeScaleWatcher);
    if (!watcher)
        return;
    m_kdeConfigDir = QDir::homePath() + QStringLiteral("/.config");
    m_kdeGlobalsPath = m_kdeConfigDir + QStringLiteral("/kdeglobals");
    m_kcmFontsPath = m_kdeConfigDir + QStringLiteral("/kcmfonts");

    const auto ensureWatched = [watcher](const QString &path, bool directory) {
        if (path.isEmpty())
            return;
        const QStringList existing = directory ? watcher->directories() : watcher->files();
        if (existing.contains(path))
            return;
        if (directory) {
            if (QDir(path).exists())
                watcher->addPath(path);
        } else {
            if (QFileInfo::exists(path))
                watcher->addPath(path);
        }
    };

    ensureWatched(m_kdeConfigDir, true);
    ensureWatched(m_kdeGlobalsPath, false);
    ensureWatched(m_kcmFontsPath, false);
    if (dprTraceEnabled())
        qInfo() << "QRoundedFrame DPR kde-watcher"
                << "dirs" << watcher->directories()
                << "files" << watcher->files();
#endif
}

int NativeWindowAgent::nativeSystemButtonHitTest(qintptr lParam) const {
#ifdef Q_OS_WIN
    if (m_hwnd) {
        HWND hwnd = reinterpret_cast<HWND>(m_hwnd);
        RECT rect = {};
        if (hwnd && GetWindowRect(hwnd, &rect)) {
            const POINT cursor = {
                static_cast<LONG>(static_cast<short>(LOWORD(lParam))),
                static_cast<LONG>(static_cast<short>(HIWORD(lParam))),
            };
            const int cornerInset = qMax(1, m_resizeCornerInset);
            if (cursor.y >= rect.top && cursor.y <= rect.top + cornerInset &&
                cursor.x >= rect.right - cornerInset - 1 && cursor.x <= rect.right) {
                return HTNOWHERE;
            }
        }
    }
    if (nativeItemContainsScreenPoint(m_minimizeButton, lParam, true))
        return HTREDUCE;
    if (nativeItemContainsScreenPoint(m_maximizeButton, lParam, true))
        return HTZOOM;
    if (nativeItemContainsScreenPoint(m_closeButton, lParam, true))
        return HTCLOSE;
#else
    Q_UNUSED(lParam)
#endif
    return 0;
}

QString NativeWindowAgent::systemButtonRoleForHit(int hit) const {
#ifdef Q_OS_WIN
    if (hit == HTREDUCE)
        return QStringLiteral("minimize");
    if (hit == HTZOOM)
        return QStringLiteral("maximize");
    if (hit == HTCLOSE)
        return QStringLiteral("close");
#else
    Q_UNUSED(hit)
#endif
    return QString();
}

void NativeWindowAgent::setNativeSystemButtonHover(int hit) {
    if (m_hoveredNativeButtonHit == hit)
        return;
    m_hoveredNativeButtonHit = hit;
    emit nativeSystemButtonHoverChanged(systemButtonRoleForHit(hit));
}

bool NativeWindowAgent::nativeItemContainsScreenPoint(QQuickItem *item, qintptr lParam) const {
    return nativeItemContainsScreenPoint(item, lParam, false);
}

bool NativeWindowAgent::nativeItemContainsScreenPoint(QQuickItem *item, qintptr lParam, bool extendToTitleBarHeight) const {
#ifdef Q_OS_WIN
    if (!m_window || !item || !item->isVisible() || !item->isEnabled())
        return false;
    const QPointF topLeft = item->mapToScene(QPointF(0.0, 0.0));
    QRectF rect(topLeft, item->size());
    if (rect.isEmpty())
        return false;
    if (extendToTitleBarHeight && m_titleBarItem) {
        const QPointF titleTopLeft = m_titleBarItem->mapToScene(QPointF(0.0, 0.0));
        const QSizeF titleSize = m_titleBarItem->size();
        if (titleSize.height() > rect.height() + 2.0) {
            rect.setTop(titleTopLeft.y());
            rect.setHeight(titleSize.height());
        }
    }
    const qreal dpr = qMax<qreal>(1.0, m_window->devicePixelRatio());
    POINT local = {
        LONG(qRound(rect.left() * dpr)),
        LONG(qRound(rect.top() * dpr)),
    };
    HWND hwnd = reinterpret_cast<HWND>(m_hwnd);
    if (!hwnd)
        return false;
    if (!ClientToScreen(hwnd, &local))
        return false;
    RECT screenRect = {
        local.x,
        local.y,
        LONG(local.x + qRound(rect.width() * dpr)),
        LONG(local.y + qRound(rect.height() * dpr)),
    };
    const POINT cursor = {
        static_cast<LONG>(static_cast<short>(LOWORD(lParam))),
        static_cast<LONG>(static_cast<short>(HIWORD(lParam))),
    };
    return PtInRect(&screenRect, cursor);
#else
    Q_UNUSED(item)
    Q_UNUSED(lParam)
    return false;
#endif
}

void NativeWindowAgent::clearWindowRegion() {
#ifdef Q_OS_WIN
    if (!m_window)
        return;
    HWND hwnd = reinterpret_cast<HWND>(m_hwnd);
    if (hwnd)
        SetWindowRgn(hwnd, nullptr, TRUE);
    m_lastRegionSize = QSize();
    m_lastRegionRadius = -1;
#elif defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    if (!m_window)
        return;
    Display *display = sharedXDisplay();
    if (!display)
        return;
    const Window windowId = static_cast<Window>(m_window->winId());
    if (windowId) {
        XShapeCombineMask(display, windowId, ShapeBounding, 0, 0, None, ShapeSet);
        XShapeCombineMask(display, windowId, ShapeInput, 0, 0, None, ShapeSet);
        XFlush(display);
    }
    m_lastRegionSize = QSize();
    m_lastRegionRadius = -1;
#endif
}

#include "native_window_agent.moc"
