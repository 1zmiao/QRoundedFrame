#include "native_widget_host_agent.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QRectF>
#include <QtCore/QtGlobal>

#ifdef Q_OS_WIN
#    include <dwmapi.h>
#    include <windows.h>
#endif

namespace {
#ifdef Q_OS_WIN
QVariantMap rectToMap(const RECT &rect)
{
    return {
        {QStringLiteral("x"), int(rect.left)},
        {QStringLiteral("y"), int(rect.top)},
        {QStringLiteral("width"), int(rect.right - rect.left)},
        {QStringLiteral("height"), int(rect.bottom - rect.top)},
    };
}
#endif
} // namespace

NativeWidgetHostAgent::NativeWidgetHostAgent(QQuickItem *parent)
    : QQuickItem(parent)
{
}

NativeWidgetHostAgent::~NativeWidgetHostAgent()
{
    uninstallFilter();
}

QString NativeWidgetHostAgent::hostHwnd() const { return m_hostHwnd; }

void NativeWidgetHostAgent::setHostHwnd(const QString &value)
{
    if (m_hostHwnd == value)
        return;
    m_hostHwnd = value;
    emit hostHwndChanged();
    installFilter();
}

bool NativeWidgetHostAgent::filterEnabled() const { return m_filterEnabled; }

void NativeWidgetHostAgent::setFilterEnabled(bool value)
{
    if (m_filterEnabled == value)
        return;
    m_filterEnabled = value;
    emit filterEnabledChanged();
    if (m_filterEnabled)
        installFilter();
    else
        uninstallFilter();
}

bool NativeWidgetHostAgent::customShadowEnabled() const { return m_customShadowEnabled; }

void NativeWidgetHostAgent::setCustomShadowEnabled(bool value)
{
    if (m_customShadowEnabled == value)
        return;
    m_customShadowEnabled = value;
    emit customShadowEnabledChanged();
    applyWindowRegion(false);
}

bool NativeWidgetHostAgent::maximized() const { return m_maximized; }

void NativeWidgetHostAgent::setMaximized(bool value)
{
    if (m_maximized == value)
        return;
    m_maximized = value;
    emit maximizedChanged();
    applyWindowRegion(false);
}

bool NativeWidgetHostAgent::fullScreen() const { return m_fullScreen; }

void NativeWidgetHostAgent::setFullScreen(bool value)
{
    if (m_fullScreen == value)
        return;
    m_fullScreen = value;
    emit fullScreenChanged();
    applyWindowRegion(false);
}

bool NativeWidgetHostAgent::snapped() const { return m_snapped; }

void NativeWidgetHostAgent::setSnapped(bool value)
{
    if (m_snapped == value)
        return;
    m_snapped = value;
    emit snappedChanged();
    applyWindowRegion(false);
}

qreal NativeWidgetHostAgent::resizeBorder() const { return m_resizeBorder; }

void NativeWidgetHostAgent::setResizeBorder(qreal value)
{
    value = qBound<qreal>(1.0, value, 32.0);
    if (qFuzzyCompare(m_resizeBorder, value))
        return;
    m_resizeBorder = value;
    emit resizeBorderChanged();
}

qreal NativeWidgetHostAgent::shadowInset() const { return m_shadowInset; }

void NativeWidgetHostAgent::setShadowInset(qreal value)
{
    value = qBound<qreal>(0.0, value, 128.0);
    if (qFuzzyCompare(m_shadowInset, value))
        return;
    m_shadowInset = value;
    emit shadowInsetChanged();
}

qreal NativeWidgetHostAgent::titleBarHeight() const { return m_titleBarHeight; }

void NativeWidgetHostAgent::setTitleBarHeight(qreal value)
{
    value = qBound<qreal>(0.0, value, 160.0);
    if (qFuzzyCompare(m_titleBarHeight, value))
        return;
    m_titleBarHeight = value;
    emit titleBarHeightChanged();
}

qreal NativeWidgetHostAgent::captionLeftA() const { return m_captionLeftA; }
qreal NativeWidgetHostAgent::captionRightA() const { return m_captionRightA; }
qreal NativeWidgetHostAgent::captionLeftB() const { return m_captionLeftB; }
qreal NativeWidgetHostAgent::captionRightB() const { return m_captionRightB; }
QVariantMap NativeWidgetHostAgent::minimizeButtonRect() const { return m_minimizeButtonRect; }
QVariantMap NativeWidgetHostAgent::maximizeButtonRect() const { return m_maximizeButtonRect; }
QVariantMap NativeWidgetHostAgent::closeButtonRect() const { return m_closeButtonRect; }

void NativeWidgetHostAgent::setCaptionLeftA(qreal value)
{
    if (qFuzzyCompare(m_captionLeftA, value))
        return;
    m_captionLeftA = value;
    emit captionMetricsChanged();
}

void NativeWidgetHostAgent::setCaptionRightA(qreal value)
{
    if (qFuzzyCompare(m_captionRightA, value))
        return;
    m_captionRightA = value;
    emit captionMetricsChanged();
}

void NativeWidgetHostAgent::setCaptionLeftB(qreal value)
{
    if (qFuzzyCompare(m_captionLeftB, value))
        return;
    m_captionLeftB = value;
    emit captionMetricsChanged();
}

void NativeWidgetHostAgent::setCaptionRightB(qreal value)
{
    if (qFuzzyCompare(m_captionRightB, value))
        return;
    m_captionRightB = value;
    emit captionMetricsChanged();
}

void NativeWidgetHostAgent::setMinimizeButtonRect(const QVariantMap &value)
{
    const QVariantMap rect = sanitizeButtonRect(value);
    if (m_minimizeButtonRect == rect)
        return;
    m_minimizeButtonRect = rect;
    emit systemButtonRectsChanged();
}

void NativeWidgetHostAgent::setMaximizeButtonRect(const QVariantMap &value)
{
    const QVariantMap rect = sanitizeButtonRect(value);
    if (m_maximizeButtonRect == rect)
        return;
    m_maximizeButtonRect = rect;
    emit systemButtonRectsChanged();
}

void NativeWidgetHostAgent::setCloseButtonRect(const QVariantMap &value)
{
    const QVariantMap rect = sanitizeButtonRect(value);
    if (m_closeButtonRect == rect)
        return;
    m_closeButtonRect = rect;
    emit systemButtonRectsChanged();
}

bool NativeWidgetHostAgent::isMaximizedNative() const
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return false;
    return IsZoomed(reinterpret_cast<HWND>(host));
#else
    return false;
#endif
}

bool NativeWidgetHostAgent::toggleMaximizedNative()
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return false;
    HWND hwnd = reinterpret_cast<HWND>(host);
    const WPARAM command = IsZoomed(hwnd) ? SC_RESTORE : SC_MAXIMIZE;
    SendMessageW(hwnd, WM_SYSCOMMAND, command, 0);
    return true;
#else
    return false;
#endif
}

bool NativeWidgetHostAgent::showMinimizedNative()
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return false;
    SendMessageW(reinterpret_cast<HWND>(host), WM_SYSCOMMAND, SC_MINIMIZE, 0);
    return true;
#else
    return false;
#endif
}

bool NativeWidgetHostAgent::showMaximizedNative()
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return false;
    SendMessageW(reinterpret_cast<HWND>(host), WM_SYSCOMMAND, SC_MAXIMIZE, 0);
    return true;
#else
    return false;
#endif
}

bool NativeWidgetHostAgent::showNormalNative()
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return false;
    SendMessageW(reinterpret_cast<HWND>(host), WM_SYSCOMMAND, SC_RESTORE, 0);
    return true;
#else
    return false;
#endif
}

bool NativeWidgetHostAgent::activateNative()
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return false;
    HWND hwnd = reinterpret_cast<HWND>(host);
    BringWindowToTop(hwnd);
    SetForegroundWindow(hwnd);
    return true;
#else
    return false;
#endif
}

bool NativeWidgetHostAgent::setTopMostNative(bool enabled, bool activate)
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return false;
    HWND hwnd = reinterpret_cast<HWND>(host);
    if (!IsWindow(hwnd))
        return false;
    const HWND insertAfter = enabled ? HWND_TOPMOST : HWND_NOTOPMOST;
    UINT flags = SWP_NOMOVE | SWP_NOSIZE | SWP_NOOWNERZORDER;
    if (!(enabled && activate))
        flags |= SWP_NOACTIVATE;
    SetWindowPos(hwnd, insertAfter, 0, 0, 0, 0, flags);
    if (enabled && activate)
        BringWindowToTop(hwnd);
    return true;
#else
    Q_UNUSED(enabled)
    Q_UNUSED(activate)
    return false;
#endif
}

bool NativeWidgetHostAgent::beginCaptionMoveNative()
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return false;
    HWND hwnd = reinterpret_cast<HWND>(host);
    ReleaseCapture();
    SendMessageW(hwnd, WM_SYSCOMMAND, SC_MOVE | HTCAPTION, 0);
    return true;
#else
    return false;
#endif
}

bool NativeWidgetHostAgent::setMouseCaptureNative(bool enabled)
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return false;
    if (enabled)
        return SetCapture(reinterpret_cast<HWND>(host)) != nullptr;
    return ReleaseCapture();
#else
    Q_UNUSED(enabled)
    return false;
#endif
}

bool NativeWidgetHostAgent::setWindowGeometryNative(int x, int y, int width, int height, bool size, bool activate)
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return false;
    UINT flags = SWP_NOZORDER | SWP_NOOWNERZORDER;
    if (!activate)
        flags |= SWP_NOACTIVATE;
    if (!size)
        flags |= SWP_NOSIZE;
    return SetWindowPos(
               reinterpret_cast<HWND>(host),
               nullptr,
               x,
               y,
               size ? width : 0,
               size ? height : 0,
               flags)
           != FALSE;
#else
    Q_UNUSED(x)
    Q_UNUSED(y)
    Q_UNUSED(width)
    Q_UNUSED(height)
    Q_UNUSED(size)
    Q_UNUSED(activate)
    return false;
#endif
}

QVariantMap NativeWidgetHostAgent::windowFrameGeometryNative() const
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return {};
    RECT rect = {};
    if (!GetWindowRect(reinterpret_cast<HWND>(host), &rect))
        return {};
    return rectToMap(rect);
#else
    return {};
#endif
}

QVariantMap NativeWidgetHostAgent::restoreBoundsNative() const
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return {};
    WINDOWPLACEMENT placement = {};
    placement.length = sizeof(WINDOWPLACEMENT);
    if (!GetWindowPlacement(reinterpret_cast<HWND>(host), &placement))
        return {};
    return rectToMap(placement.rcNormalPosition);
#else
    return {};
#endif
}

bool NativeWidgetHostAgent::setRestoreBoundsNative(int x, int y, int width, int height)
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return false;
    HWND hwnd = reinterpret_cast<HWND>(host);
    WINDOWPLACEMENT placement = {};
    placement.length = sizeof(WINDOWPLACEMENT);
    if (!GetWindowPlacement(hwnd, &placement))
        return false;
    placement.rcNormalPosition.left = x;
    placement.rcNormalPosition.top = y;
    placement.rcNormalPosition.right = x + width;
    placement.rcNormalPosition.bottom = y + height;
    return SetWindowPlacement(hwnd, &placement) != FALSE;
#else
    Q_UNUSED(x)
    Q_UNUSED(y)
    Q_UNUSED(width)
    Q_UNUSED(height)
    return false;
#endif
}

bool NativeWidgetHostAgent::forceNormalGeometryNative(int x, int y, int width, int height)
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return false;
    HWND hwnd = reinterpret_cast<HWND>(host);
    WINDOWPLACEMENT placement = {};
    placement.length = sizeof(WINDOWPLACEMENT);
    if (GetWindowPlacement(hwnd, &placement)) {
        placement.flags = 0;
        placement.showCmd = SW_SHOWNORMAL;
        placement.rcNormalPosition.left = x;
        placement.rcNormalPosition.top = y;
        placement.rcNormalPosition.right = x + width;
        placement.rcNormalPosition.bottom = y + height;
        SetWindowPlacement(hwnd, &placement);
    }
    ShowWindow(hwnd, SW_RESTORE);
    return SetWindowPos(
               hwnd,
               nullptr,
               x,
               y,
               width,
               height,
               SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED)
           != FALSE;
#else
    Q_UNUSED(x)
    Q_UNUSED(y)
    Q_UNUSED(width)
    Q_UNUSED(height)
    return false;
#endif
}

void NativeWidgetHostAgent::setShellBackgroundColor(const QColor &color)
{
    if (m_shellBackgroundColor == color)
        return;
    m_shellBackgroundColor = color;
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (host)
        InvalidateRect(reinterpret_cast<HWND>(host), nullptr, FALSE);
#endif
}

void NativeWidgetHostAgent::setCornerRadius(int radius)
{
    const int value = qBound(0, radius, 96);
    if (m_cornerRadius == value)
        return;
    m_cornerRadius = value;
    applyWindowRegion(false);
}

bool NativeWidgetHostAgent::applyWindowsChromeNative()
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return false;
    HWND hwnd = reinterpret_cast<HWND>(host);
    if (!IsWindow(hwnd))
        return false;

    LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_STYLE);
    style |= WS_THICKFRAME | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX;
    SetWindowLongPtrW(hwnd, GWL_STYLE, style);
    SetWindowPos(
        hwnd,
        nullptr,
        0,
        0,
        0,
        0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);

    const int cornerPreference = m_customShadowEnabled ? 2 /* DWMWCP_ROUND */ : 0 /* DWMWCP_DEFAULT */;
    DwmSetWindowAttribute(hwnd, 33 /* DWMWA_WINDOW_CORNER_PREFERENCE */, &cornerPreference, sizeof(cornerPreference));

    const int ncRenderingPolicy = 2 /* DWMNCRP_ENABLED */;
    DwmSetWindowAttribute(hwnd, 2 /* DWMWA_NCRENDERING_POLICY */, &ncRenderingPolicy, sizeof(ncRenderingPolicy));

    const DWORD borderColor = 0xFFFFFFFE /* DWMWA_COLOR_NONE */;
    DwmSetWindowAttribute(hwnd, 34 /* DWMWA_BORDER_COLOR */, &borderColor, sizeof(borderColor));

    const MARGINS margins = m_customShadowEnabled ? MARGINS{0, 0, 0, 0} : MARGINS{1, 1, 1, 1};
    DwmExtendFrameIntoClientArea(hwnd, &margins);
    applyWindowRegion(false);
    return true;
#else
    return false;
#endif
}

void NativeWidgetHostAgent::componentComplete()
{
    QQuickItem::componentComplete();
    installFilter();
}

void NativeWidgetHostAgent::installFilter()
{
    if (m_filterInstalled || !m_filterEnabled || !qApp || parsedHwnd() == 0)
        return;
    qApp->installNativeEventFilter(this);
    m_filterInstalled = true;
}

void NativeWidgetHostAgent::uninstallFilter()
{
    if (!m_filterInstalled || !qApp)
        return;
    qApp->removeNativeEventFilter(this);
    m_filterInstalled = false;
}

quintptr NativeWidgetHostAgent::parsedHwnd() const
{
    bool ok = false;
    const quintptr value = m_hostHwnd.trimmed().toULongLong(&ok, 10);
    return ok ? value : 0;
}

int NativeWidgetHostAgent::nativeCornerRadiusPx(int radius, quintptr host) const
{
#ifdef Q_OS_WIN
    if (radius <= 0)
        return 0;
    UINT dpi = 96;
    HWND hwnd = reinterpret_cast<HWND>(host);
    if (hwnd) {
        if (auto getDpiForWindow = reinterpret_cast<UINT(WINAPI *)(HWND)>(
                GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForWindow"))) {
            dpi = getDpiForWindow(hwnd);
        }
    }
    const int scaledRadius = qMax(1, MulDiv(radius, int(dpi), 96));
    return qMax(1, scaledRadius + 1);
#else
    Q_UNUSED(radius)
    Q_UNUSED(host)
    return 0;
#endif
}

void NativeWidgetHostAgent::clearWindowRegion(bool redraw)
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return;
    SetWindowRgn(reinterpret_cast<HWND>(host), nullptr, redraw ? TRUE : FALSE);
    m_lastRegionSize = QSize();
    m_lastRegionRadius = -1;
#else
    Q_UNUSED(redraw)
#endif
}

void NativeWidgetHostAgent::applyWindowRegion(bool redraw)
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return;
    HWND hwnd = reinterpret_cast<HWND>(host);
    RECT rect = {};
    if (!GetWindowRect(hwnd, &rect))
        return;
    applyWindowRegionForNativeSize(rect.right - rect.left, rect.bottom - rect.top, redraw);
#else
    Q_UNUSED(redraw)
#endif
}

void NativeWidgetHostAgent::applyWindowRegionForNativeSize(int width, int height, bool redraw)
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host || width <= 0 || height <= 0)
        return;
    HWND hwnd = reinterpret_cast<HWND>(host);
    if (!m_customShadowEnabled) {
        clearWindowRegion(redraw);
        return;
    }
    const bool square = m_cornerRadius <= 0 || m_maximized || m_fullScreen || m_snapped || IsZoomed(hwnd);
    const int radius = square ? 0 : nativeCornerRadiusPx(m_cornerRadius, host);
    const QSize size(width, height);
    if (m_lastRegionSize == size && m_lastRegionRadius == radius)
        return;
    HRGN region = square
                      ? CreateRectRgn(0, 0, width + 1, height + 1)
                      : CreateRoundRectRgn(0, 0, width + 1, height + 1, radius * 2, radius * 2);
    if (!region)
        return;
    if (SetWindowRgn(hwnd, region, redraw ? TRUE : FALSE)) {
        m_lastRegionSize = size;
        m_lastRegionRadius = radius;
        return;
    }
    DeleteObject(region);
#else
    Q_UNUSED(width)
    Q_UNUSED(height)
    Q_UNUSED(redraw)
#endif
}

void NativeWidgetHostAgent::fillHostWindowBackground()
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return;
    HWND hwnd = reinterpret_cast<HWND>(host);
    RECT rect = {};
    if (!GetClientRect(hwnd, &rect))
        return;
    HDC hdc = GetDC(hwnd);
    if (!hdc)
        return;
    const QColor color = m_shellBackgroundColor.isValid()
                             ? m_shellBackgroundColor
                             : QColor(16, 18, 24);
    HBRUSH brush = CreateSolidBrush(RGB(color.red(), color.green(), color.blue()));
    if (brush) {
        FillRect(hdc, &rect, brush);
        DeleteObject(brush);
    }
    ReleaseDC(hwnd, hdc);
#endif
}

bool NativeWidgetHostAgent::nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result)
{
#ifdef Q_OS_WIN
    if (!m_filterEnabled || !message)
        return false;
    if (eventType != QByteArrayLiteral("windows_generic_MSG")
        && eventType != QByteArrayLiteral("windows_dispatcher_MSG")) {
        return false;
    }

    const quintptr host = parsedHwnd();
    if (!host)
        return false;
    MSG *msg = static_cast<MSG *>(message);
    HWND hwnd = reinterpret_cast<HWND>(host);
    if (!msg->hwnd || !hwnd)
        return false;

    const bool messageForHost = msg->hwnd == hwnd;
    const bool messageForHostChild = !messageForHost && IsChild(hwnd, msg->hwnd);
    if (!messageForHost && !messageForHostChild)
        return false;

    switch (msg->message) {
    case WM_NCHITTEST: {
        LRESULT dwmResult = 0;
        if (messageForHost && DwmDefWindowProc(hwnd, msg->message, msg->wParam, msg->lParam, &dwmResult)) {
            if (dwmResult == HTREDUCE || dwmResult == HTZOOM || dwmResult == HTCLOSE) {
                if (result)
                    *result = dwmResult;
                return true;
            }
        }
        const int hit = hitTest(msg->lParam);
        if (hit != 0) {
            if (result)
                *result = hit;
            return true;
        }
        break;
    }
    case WM_NCMOUSEMOVE:
    case WM_NCMOUSELEAVE: {
        LRESULT dwmResult = 0;
        if (messageForHost && DwmDefWindowProc(hwnd, msg->message, msg->wParam, msg->lParam, &dwmResult)) {
            if (result)
                *result = dwmResult;
            return true;
        }
        const int hitCode = int(msg->wParam & 0xFFFF);
        if (messageForHost && (hitCode == HTREDUCE || hitCode == HTZOOM || hitCode == HTCLOSE)) {
            if (result)
                *result = DefWindowProcW(hwnd, msg->message, msg->wParam, msg->lParam);
            return true;
        }
        break;
    }
    default:
        break;
    }

    if (!messageForHost)
        return false;

    switch (msg->message) {
    case WM_ERASEBKGND: {
        HDC hdc = reinterpret_cast<HDC>(msg->wParam);
        if (!hdc)
            return false;
        RECT rect = {};
        if (!GetClientRect(hwnd, &rect))
            return false;
        const QColor color = m_shellBackgroundColor.isValid()
                                 ? m_shellBackgroundColor
                                 : QColor(16, 18, 24);
        HBRUSH brush = CreateSolidBrush(RGB(color.red(), color.green(), color.blue()));
        if (!brush)
            return false;
        FillRect(hdc, &rect, brush);
        DeleteObject(brush);
        if (result)
            *result = 1;
        return true;
    }
    case WM_NCCALCSIZE:
        if (result)
            *result = 0;
        return true;
    case WM_ENTERSIZEMOVE:
        m_inNativeSizeMove = true;
        clearWindowRegion(false);
        emit nativeSizeMoveStarted();
        break;
    case WM_EXITSIZEMOVE:
        m_inNativeSizeMove = false;
        applyWindowRegion(false);
        emit nativeSizeMoveFinished();
        break;
    case WM_SIZING:
        fillHostWindowBackground();
        emit sizingOrPositionChanging();
        break;
    case WM_WINDOWPOSCHANGING:
        fillHostWindowBackground();
        if (!m_inNativeSizeMove) {
            WINDOWPOS *pos = reinterpret_cast<WINDOWPOS *>(msg->lParam);
            if (pos && !(pos->flags & SWP_NOSIZE))
                applyWindowRegionForNativeSize(pos->cx, pos->cy, false);
        }
        emit sizingOrPositionChanging();
        break;
    case WM_MOVING:
        emit moving();
        break;
    case WM_WINDOWPOSCHANGED:
        fillHostWindowBackground();
        if (!m_inNativeSizeMove) {
            applyWindowRegion(false);
        }
        emit windowPositionChanged();
        break;
    case WM_NCRBUTTONDOWN:
    case WM_NCRBUTTONUP:
        if ((msg->wParam & 0xFFFF) == HTCAPTION) {
            if (result)
                *result = 0;
            return true;
        }
        break;
    case WM_CONTEXTMENU: {
        const int hit = hitTest(msg->lParam);
        if (hit == HTCAPTION) {
            if (result)
                *result = 0;
            return true;
        }
        break;
    }
    case WM_NCLBUTTONDOWN:
        if ((msg->wParam & 0xFFFF) == HTCAPTION) {
            return false;
        }
        break;
    default:
        break;
    }
#else
    Q_UNUSED(eventType)
    Q_UNUSED(message)
    Q_UNUSED(result)
#endif
    return false;
}

bool NativeWidgetHostAgent::captionHitTest(qreal localX, qreal localY) const
{
    if (m_fullScreen)
        return false;
    if (localY < 0.0 || localY > m_titleBarHeight)
        return false;

    const bool hasA = m_captionRightA > m_captionLeftA + 2.0;
    const bool hasB = m_captionRightB > m_captionLeftB + 2.0;
    if (hasA || hasB) {
        if (hasA && localX >= m_captionLeftA && localX <= m_captionRightA)
            return true;
        if (hasB && localX >= m_captionLeftB && localX <= m_captionRightB)
            return true;
        return false;
    }

    const qreal rightBlock = 170.0;
    const qreal contentWidth = qMax<qreal>(0.0, width() - m_shadowInset * 2.0);
    return localX >= 0.0 && localX <= qMax<qreal>(0.0, contentWidth - rightBlock);
}

QVariantMap NativeWidgetHostAgent::sanitizeButtonRect(const QVariantMap &value) const
{
    QVariantMap rect;
    bool ok = false;
    const qreal x = value.value(QStringLiteral("x")).toReal(&ok);
    if (!ok)
        return {};
    const qreal y = value.value(QStringLiteral("y")).toReal(&ok);
    if (!ok)
        return {};
    const qreal width = value.value(QStringLiteral("width")).toReal(&ok);
    if (!ok || width <= 0.0)
        return {};
    const qreal height = value.value(QStringLiteral("height")).toReal(&ok);
    if (!ok || height <= 0.0)
        return {};
    rect.insert(QStringLiteral("x"), x);
    rect.insert(QStringLiteral("y"), y);
    rect.insert(QStringLiteral("width"), width);
    rect.insert(QStringLiteral("height"), height);
    return rect;
}

int NativeWidgetHostAgent::systemButtonHitTest(qreal localX, qreal localY) const
{
#ifdef Q_OS_WIN
    auto contains = [this, localX, localY](const QVariantMap &rect) {
        if (rect.isEmpty())
            return false;
        const qreal x = rect.value(QStringLiteral("x")).toReal();
        const qreal width = rect.value(QStringLiteral("width")).toReal();
        const qreal height = rect.value(QStringLiteral("height")).toReal();
        const qreal y = m_titleBarHeight > height + 2.0
                            ? 0.0
                            : rect.value(QStringLiteral("y")).toReal();
        const qreal effectiveHeight = m_titleBarHeight > height + 2.0
                                          ? m_titleBarHeight
                                          : height;
        const QRectF bounds(x, y, width, effectiveHeight);
        return bounds.contains(QPointF(localX, localY));
    };
    if (contains(m_minimizeButtonRect))
        return HTREDUCE;
    if (contains(m_maximizeButtonRect))
        return HTZOOM;
    if (contains(m_closeButtonRect))
        return HTCLOSE;
    const int inferredHit = inferredSystemButtonHitTest(localX, localY);
    if (inferredHit != 0)
        return inferredHit;
#endif
    return 0;
}

int NativeWidgetHostAgent::inferredSystemButtonHitTest(qreal localX, qreal localY) const
{
#ifdef Q_OS_WIN
    if (localY < 0.0 || localY > m_titleBarHeight)
        return 0;

    const qreal buttonWidth = m_maximizeButtonRect.value(QStringLiteral("width"), 0.0).toReal();
    const qreal buttonHeight = m_maximizeButtonRect.value(QStringLiteral("height"), 0.0).toReal();
    const qreal closeX = m_closeButtonRect.value(QStringLiteral("x"), 0.0).toReal();
    if (buttonWidth <= 8.0 || buttonHeight <= 8.0 || closeX <= 0.0)
        return 0;

    const QRectF inferredMaximize(closeX - buttonWidth, m_closeButtonRect.value(QStringLiteral("y"), 0.0).toReal(), buttonWidth, buttonHeight);
    if (inferredMaximize.contains(QPointF(localX, localY)))
        return HTZOOM;
#else
    Q_UNUSED(localX)
    Q_UNUSED(localY)
#endif
    return 0;
}

int NativeWidgetHostAgent::hitTest(qintptr lparam) const
{
#ifdef Q_OS_WIN
    const quintptr host = parsedHwnd();
    if (!host)
        return 0;
    HWND hwnd = reinterpret_cast<HWND>(host);
    RECT rect = {};
    if (!GetWindowRect(hwnd, &rect))
        return 0;

    const int x = static_cast<short>(LOWORD(lparam));
    const int y = static_cast<short>(HIWORD(lparam));
    UINT dpi = 96;
    if (auto getDpiForWindow = reinterpret_cast<UINT(WINAPI *)(HWND)>(
            GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForWindow"))) {
        dpi = getDpiForWindow(hwnd);
    }
    const qreal scale = qMax<qreal>(1.0, qreal(dpi) / 96.0);
    const int border = qMax(1, qRound(m_resizeBorder * scale));
    const int corner = qMax(border, qRound(5.0 * scale));
    int insetPx = m_customShadowEnabled && !m_maximized && !m_fullScreen && !m_snapped
                      ? qMax(0, qRound(m_shadowInset * scale))
                      : 0;

    int visualLeft = rect.left + insetPx;
    int visualTop = rect.top + insetPx;
    int visualRight = rect.right - insetPx;
    int visualBottom = rect.bottom - insetPx;
    if (visualRight <= visualLeft + border * 2 || visualBottom <= visualTop + border * 2) {
        visualLeft = rect.left;
        visualTop = rect.top;
        visualRight = rect.right;
        visualBottom = rect.bottom;
        insetPx = 0;
    }

    if (insetPx > 0 && !(visualLeft <= x && x < visualRight && visualTop <= y && y < visualBottom)) {
        activateWindowBeneathPoint(x, y);
        return HTTRANSPARENT;
    }

    if (!m_maximized && !m_fullScreen) {
        const bool leftCorner = visualLeft <= x && x < visualLeft + corner;
        const bool rightCorner = visualRight - corner <= x && x < visualRight;
        const bool topCorner = visualTop <= y && y < visualTop + corner;
        const bool bottomCorner = visualBottom - corner <= y && y < visualBottom;
        const bool left = visualLeft <= x && x < visualLeft + border;
        const bool right = visualRight - border <= x && x < visualRight;
        const bool top = visualTop <= y && y < visualTop + border;
        const bool bottom = visualBottom - border <= y && y < visualBottom;
        if (topCorner && leftCorner)
            return HTTOPLEFT;
        if (topCorner && rightCorner)
            return HTTOPRIGHT;
        if (bottomCorner && leftCorner)
            return HTBOTTOMLEFT;
        if (bottomCorner && rightCorner)
            return HTBOTTOMRIGHT;
        if (left)
            return HTLEFT;
        if (right)
            return HTRIGHT;
        if (top)
            return HTTOP;
        if (bottom)
            return HTBOTTOM;
    }

    const qreal localX = (qreal(x - visualLeft) / scale);
    const qreal localY = (qreal(y - visualTop) / scale);
    const int buttonHit = systemButtonHitTest(localX, localY);
    if (buttonHit != 0)
        return buttonHit;
    if (captionHitTest(localX, localY))
        return HTCAPTION;
#endif
    return 0;
}

void NativeWidgetHostAgent::activateWindowBeneathPoint(int x, int y) const
{
#ifdef Q_OS_WIN
    if (!(GetAsyncKeyState(VK_LBUTTON) & 0x8000)
        && !(GetAsyncKeyState(VK_RBUTTON) & 0x8000)
        && !(GetAsyncKeyState(VK_MBUTTON) & 0x8000)) {
        return;
    }
    const quintptr host = parsedHwnd();
    POINT pt = {x, y};
    HWND target = WindowFromPoint(pt);
    if (!target || reinterpret_cast<quintptr>(target) == host)
        return;
    HWND root = GetAncestor(target, GA_ROOT);
    if (root && reinterpret_cast<quintptr>(root) != host) {
        SetForegroundWindow(root);
        BringWindowToTop(root);
    }
#else
    Q_UNUSED(x)
    Q_UNUSED(y)
#endif
}

#include "native_widget_host_agent.moc"
