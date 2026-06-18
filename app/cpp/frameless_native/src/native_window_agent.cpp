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
#    include "native_window_agent_linux_p.h"
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

NativeWindowAgent::NativeWindowAgent(QObject *parent)
    : QWK::QuickWindowAgent(parent)
{
}

NativeWindowAgent::~NativeWindowAgent() {
    teardown();
}

bool NativeWindowAgent::nativeSystemMoveActive() const {
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    return m_linuxSystemMoveActive;
#else
    return false;
#endif
}

bool NativeWindowAgent::nativeSystemMoveFromMaximized() const {
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    return m_linuxSystemMoveFromMaximized;
#else
    return false;
#endif
}

void NativeWindowAgent::setup(QQuickWindow *window) {
    if (!window)
        return;
    if (m_window && m_window != window) {
        m_window->removeEventFilter(this);
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
        disconnect(m_window.data(), nullptr, this, nullptr);
#endif
    }
    m_window = window;
    m_window->installEventFilter(this);
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    connect(m_window.data(), &QWindow::screenChanged, this, [this](QScreen *) {
        refreshScreenConnections();
        refreshNativeMetrics("window-screen-changed");
    });
    if (!m_clientSideShadowMode)
        QWK::QuickWindowAgent::setup(window);
#else
    QWK::QuickWindowAgent::setup(window);
#endif
    m_window->setColor(shellBackgroundColor());
#ifdef Q_OS_WIN
    m_hwnd = reinterpret_cast<void *>(m_window->winId());
#endif
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    if (!m_clientSideShadowMode)
        QWK::QuickWindowAgent::setWindowAttribute(QStringLiteral("no-system-menu"), true);
#else
    QWK::QuickWindowAgent::setWindowAttribute(QStringLiteral("no-system-menu"), true);
    setResizeHitTestInsets(6, 8);
#endif
    installNativeShellFilter();
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    refreshScreenConnections();
    installX11RootPropertyListener();
    installKdeScaleWatcher();
    refreshNativeMetrics("setup");
#else
    applyWindowAttributes();
#endif
}

void NativeWindowAgent::teardown() {
    uninstallNativeShellFilter();
    restoreClassBackgroundBrush();
    if (m_window)
        m_window->removeEventFilter(this);
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    if (m_screen)
        disconnect(m_screen.data(), nullptr, this, nullptr);
#endif
    m_window.clear();
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    m_screen.clear();
#endif
    m_titleBarItem.clear();
    m_minimizeButton.clear();
    m_maximizeButton.clear();
    m_closeButton.clear();
    m_lastRegionSize = QSize();
    m_lastRegionRadius = -1;
    m_inNativeSizeMove = false;
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    m_linuxSystemMoveActive = false;
    m_linuxCsdFullInset = 0;
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
#endif
#ifdef Q_OS_WIN
    m_hwnd = nullptr;
#endif
}

void NativeWindowAgent::setTitleBar(QQuickItem *item) {
    if (item) {
        m_titleBarItem = item;
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
        if (!m_clientSideShadowMode)
            QWK::QuickWindowAgent::setTitleBar(item);
#else
        QWK::QuickWindowAgent::setTitleBar(item);
#endif
    }
}

void NativeWindowAgent::setSystemButton(const QString &role, QQuickItem *item) {
    if (!item)
        return;
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    if (m_clientSideShadowMode)
        return;
#endif
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
    if (!item)
        return;
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    if (m_clientSideShadowMode)
        return;
#endif
    if (item)
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
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    if (!m_clientSideShadowMode) {
        setWindowAttribute(QStringLiteral("qrounded-resize-edge-inset"), edge);
        setWindowAttribute(QStringLiteral("qrounded-resize-corner-inset"), corner);
    }
#else
    setWindowAttribute(QStringLiteral("qrounded-resize-edge-inset"), edge);
    setWindowAttribute(QStringLiteral("qrounded-resize-corner-inset"), corner);
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
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
            // WM has processed the state change (maximized -> windowed).
            // Release the extents lock so QML can resume normal sync.
            m_linuxSystemMoveExtentsLocked = false;
#endif
            applyWindowAttributes();
            break;
        case QEvent::DevicePixelRatioChange:
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
            traceNativeMetrics("event-dpr-change");
#endif
            applyWindowAttributes();
            break;
        case QEvent::Resize:
#ifdef Q_OS_WIN
            if (m_inNativeSizeMove) {
                fillWindowBackground();
            } else
#endif
            {
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
                if (m_clientSideShadowMode) {
                    clearWindowRegion();
                    applyClientSideShadowInputRegion();
                } else
#endif
                {
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

    switch (msg->message) {
    case WM_NCHITTEST:
    case WM_NCMOUSEMOVE:
    case WM_NCLBUTTONDOWN:
    case WM_NCLBUTTONUP:
    case WM_NCLBUTTONDBLCLK:
    case WM_NCRBUTTONDOWN:
    case WM_NCRBUTTONUP:
    case WM_NCRBUTTONDBLCLK:
    case WM_NCMBUTTONDOWN:
    case WM_NCMBUTTONUP:
    case WM_NCMBUTTONDBLCLK:
    case WM_NCXBUTTONDOWN:
    case WM_NCXBUTTONUP:
    case WM_NCXBUTTONDBLCLK:
    case WM_NCPOINTERUPDATE:
    case WM_NCPOINTERDOWN:
    case WM_NCPOINTERUP:
    case WM_NCMOUSEHOVER:
        // Let QWindowKit own the full non-client input state machine. The
        // project filter only handles shell-specific region/background/close
        // behavior below; duplicating chrome hit-test and button press logic
        // here races QWindowKit's cached hit-test state on fast drag/snap paths.
        return false;
    case WM_NCMOUSELEAVE:
        setNativeSystemButtonHover(HTNOWHERE);
        return false;
    default:
        break;
    }

    switch (msg->message) {
    case WM_LBUTTONUP:
    case WM_CANCELMODE:
    case WM_CAPTURECHANGED:
        m_pressedNativeButtonHit = 0;
        break;
    case WM_MOUSEMOVE:
        setNativeSystemButtonHover(HTNOWHERE);
        break;
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
    const bool isSynthetic = event->response_type & 0x80;
    switch (responseType) {
    case XCB_BUTTON_RELEASE:
        // Reject non-synthetic ButtonRelease: the one from XUngrabPointer
        // is generated by the X server (no 0x80 bit), while WM-sent events
        // arrive via XSendEvent and carry the 0x80 send_event flag.
        if (!isSynthetic)
            break;
        m_linuxSystemMoveActive = false;
        m_linuxSystemMoveFromMaximized = false;
        m_linuxSystemMoveExtentsLocked = false;
        emit nativeSystemMoveActiveChanged();
        emit nativeSystemMoveFinished();
        break;
    case XCB_UNMAP_NOTIFY:
        m_linuxSystemMoveActive = false;
        m_linuxSystemMoveFromMaximized = false;
        m_linuxSystemMoveExtentsLocked = false;
        emit nativeSystemMoveActiveChanged();
        emit nativeSystemMoveFinished();
        break;
    case XCB_FOCUS_OUT:
    case XCB_LEAVE_NOTIFY:
        // These are transitional during WM-driven maximized restore on Xfwm4.
        // Treating them as move-finished lets QML resync while the pointer is
        // still owned by the WM, which randomly offsets the restored CSD frame.
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
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    if (m_clientSideShadowMode) {
        // Compute extents from the actual window state instead of stale
        // m_gtkFrameExtents, which may still hold the windowed value during
        // compositor-initiated transitions (edge-snap maximize, etc.).
        const bool maximized = m_window->visibility() == QWindow::Maximized
                               || m_window->visibility() == QWindow::FullScreen;
        const int inset = maximized ? 0 : m_linuxCsdFullInset;
        setGtkFrameExtentsForWindow(m_window, QMargins(inset, inset, inset, inset), effectiveDevicePixelRatio());
        setX11NormalWindowTypeForDesktop(m_window);
        clearWindowRegion();
        applyClientSideShadowInputRegion();
    } else if (m_customShadow) {
        setGtkFrameExtentsForWindow(m_window, m_gtkFrameExtents, effectiveDevicePixelRatio());
        applyWindowRegion(false);
    } else {
        setGtkFrameExtentsForWindow(m_window, m_gtkFrameExtents, effectiveDevicePixelRatio());
        clearWindowRegion();
    }
#elif defined(Q_OS_LINUX)
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
#else
    if (m_customShadow) {
        applyWindowRegion(false);
    } else {
        clearWindowRegion();
    }
#endif
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
