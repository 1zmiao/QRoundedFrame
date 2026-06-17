#include "native_window_agent.h"

#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
#include "native_window_agent_linux_p.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QDebug>
#include <QtCore/QDir>
#include <QtCore/QFileInfo>
#include <QtCore/QFileSystemWatcher>
#include <QtCore/QMargins>
#include <QtCore/QRegularExpression>
#include <QtCore/QSettings>
#include <QtGui/QGuiApplication>
#include <QtGui/QScreen>
#include <QtGui/QWindow>
#include <QtGui/qguiapplication_platform.h>
#include <xcb/xcb.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/extensions/shape.h>

#include <cmath>

Display *sharedXDisplay() {
    static Display *display = nullptr;
    static bool initialized = false;
    if (!initialized) {
        initialized = true;
        display = XOpenDisplay(nullptr);
    }
    return display;
}

bool canUseX11Shape() {
    Display *display = sharedXDisplay();
    if (!display)
        return false;
    int eventBase = 0;
    int errorBase = 0;
    return QGuiApplication::platformName().compare(QStringLiteral("xcb"), Qt::CaseInsensitive) == 0
           && XShapeQueryExtension(display, &eventBase, &errorBase);
}

qreal normalizedDpr(qreal dpr) {
    return qMax<qreal>(1.0, dpr > 0.0 ? dpr : 1.0);
}

int nativeCornerRadiusPx(int radius, qreal dpr) {
    if (radius <= 0)
        return 0;
    return qMax(1, int(std::lround(qreal(radius) * normalizedDpr(dpr))));
}

int nativePx(int value, qreal dpr) {
    if (value <= 0)
        return 0;
    return qMax(1, int(std::lround(qreal(value) * normalizedDpr(dpr))));
}

QSize nativeSizePx(const QSize &size, qreal dpr) {
    if (!size.isValid())
        return {};
    const qreal scale = normalizedDpr(dpr);
    return QSize(qMax(1, int(std::lround(qreal(size.width()) * scale))),
                 qMax(1, int(std::lround(qreal(size.height()) * scale))));
}

QSize x11WindowSizePx(Display *display, Window window) {
    if (!display || !window)
        return {};
    XWindowAttributes attrs = {};
    if (XGetWindowAttributes(display, window, &attrs) && attrs.width > 0 && attrs.height > 0)
        return QSize(attrs.width, attrs.height);
    return {};
}

bool dprTraceEnabled() {
    return qEnvironmentVariableIsSet("QROUNDEDFRAME_DPR_TRACE");
}

qreal readXftDpiDpr(Display *display) {
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

qreal readKdeScaleFactorDpr() {
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

XRectangle makeRect(short x, short y, unsigned short width, unsigned short height) {
    XRectangle rect = {};
    rect.x = x;
    rect.y = y;
    rect.width = width;
    rect.height = height;
    return rect;
}

void setGtkFrameExtentsForWindow(QWindow *window, const QMargins &margins, qreal dpr) {
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

QString linuxDesktopText()
{
    const QString desktop = QStringList{
        QString::fromLocal8Bit(qgetenv("XDG_CURRENT_DESKTOP")),
        QString::fromLocal8Bit(qgetenv("XDG_SESSION_DESKTOP")),
        QString::fromLocal8Bit(qgetenv("DESKTOP_SESSION")),
    }.join(u';').toLower();
    return desktop;
}

bool desktopNeedsNormalWindowType()
{
    const QString desktop = linuxDesktopText();
    return desktop.contains(QStringLiteral("mate"))
        || desktop.contains(QStringLiteral("xfce"));
}

void setX11NormalWindowTypeForDesktop(QWindow *window) {
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

bool sendNetWmMoveResize(QWindow *window) {
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

void releaseQtMouseGrab(QQuickWindow *window) {
    if (!window)
        return;
    if (QQuickItem *grabber = window->mouseGrabberItem())
        grabber->ungrabMouse();
}

bool prefersEwmhSystemMove() {
    const QString desktop = linuxDesktopText();
    return desktop.contains(QStringLiteral("cinnamon"))
        || desktop.contains(QStringLiteral("mate"))
        || desktop.contains(QStringLiteral("xfce"))
        || desktop.contains(QStringLiteral("kde"))
        || desktop.contains(QStringLiteral("plasma"));
}

bool desktopIsXfce()
{
    return linuxDesktopText().contains(QStringLiteral("xfce"));
}

void NativeWindowAgent::setClientSideShadowMode(bool enabled) {
    m_clientSideShadowMode = enabled;
    applyWindowAttributes();
}

void NativeWindowAgent::setGtkFrameExtents(int left, int top, int right, int bottom) {
    if (m_linuxSystemMoveExtentsLocked)
        return;
    m_gtkFrameExtents = QMargins(qBound(0, left, 128),
                                 qBound(0, top, 128),
                                 qBound(0, right, 128),
                                 qBound(0, bottom, 128));
    if (left > 0)
        m_linuxCsdFullInset = left;
    if (m_window)
        setGtkFrameExtentsForWindow(m_window, m_gtkFrameExtents, effectiveDevicePixelRatio());
}

bool NativeWindowAgent::startSystemMove(QQuickWindow *window, int shadowInset) {
    QQuickWindow *target = window ? window : m_window.data();
    if (!target)
        return false;

    if (m_clientSideShadowMode) {
        m_linuxSystemMoveExtentsLocked = false;

        releaseQtMouseGrab(target);
        const bool wasMaximized = target->visibility() == QWindow::Maximized
                                  || target->visibility() == QWindow::FullScreen;
        const bool xfceMaximizedRestoreMove = desktopIsXfce() && wasMaximized;
        if (xfceMaximizedRestoreMove && shadowInset > 0) {
            setGtkFrameExtentsForWindow(target, QMargins(shadowInset, shadowInset, shadowInset, shadowInset),
                                        target->devicePixelRatio());
        }
        bool sent = prefersEwmhSystemMove()
                    ? sendNetWmMoveResize(target)
                    : target->startSystemMove() || sendNetWmMoveResize(target);
        if (sent) {
            m_linuxSystemMoveActive = true;
            m_linuxSystemMoveFromMaximized = xfceMaximizedRestoreMove;
            m_linuxSystemMoveExtentsLocked = xfceMaximizedRestoreMove;
            if (m_linuxSystemMoveFromMaximized)
                emit nativeSystemMoveActiveChanged();
            return true;
        }
    }
    return false;
}

void NativeWindowAgent::applyClientSideShadowInputRegion() {
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
    const bool maximized = m_window->visibility() == QWindow::Maximized
                           || m_window->visibility() == QWindow::FullScreen;
    const int extent = maximized ? 0 : m_linuxCsdFullInset;
    const int left = qBound(0, nativePx(extent, dpr), size.width());
    const int top = qBound(0, nativePx(extent, dpr), size.height());
    const int right = qBound(0, nativePx(extent, dpr), qMax(0, size.width() - left));
    const int bottom = qBound(0, nativePx(extent, dpr), qMax(0, size.height() - top));
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
}

void NativeWindowAgent::installX11RootPropertyListener() {
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
}

void NativeWindowAgent::installKdeScaleWatcher() {
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
}

void NativeWindowAgent::refreshKdeScaleWatcherPaths() {
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
}

#endif
