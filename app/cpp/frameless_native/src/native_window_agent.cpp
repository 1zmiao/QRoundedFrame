#include "native_window_agent.h"

#include <QWKCore/windowagentbase.h>
#include <QWKQuick/quickwindowagent.h>

#include <QtCore/QMargins>
#include <QtCore/QString>
#include <QtCore/QVariant>
#include <QtCore/QtGlobal>

#ifdef Q_OS_WIN
#    include <dwmapi.h>
#    include <windows.h>
#endif

#ifdef Q_OS_WIN
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
    if (m_window)
        m_window->removeEventFilter(this);
}

void NativeWindowAgent::setup(QQuickWindow *window) {
    if (!window)
        return;
    if (m_window && m_window != window)
        m_window->removeEventFilter(this);
    m_window = window;
    m_window->installEventFilter(this);
    QWK::QuickWindowAgent::setup(window);
    applyWindowAttributes();
}

void NativeWindowAgent::setTitleBar(QQuickItem *item) {
    if (item)
        QWK::QuickWindowAgent::setTitleBar(item);
}

void NativeWindowAgent::setSystemButton(const QString &role, QQuickItem *item) {
    if (!item)
        return;
    const int button = systemButtonRole(role);
    if (button != QWK::WindowAgentBase::Unknown)
        QWK::QuickWindowAgent::setSystemButton(
            static_cast<QWK::WindowAgentBase::SystemButton>(button), item);
}

void NativeWindowAgent::setHitTestVisible(QQuickItem *item, bool visible) {
    if (item)
        QWK::QuickWindowAgent::setHitTestVisible(item, visible);
}

void NativeWindowAgent::setCustomShadowEnabled(bool enabled) {
    m_customShadow = enabled;
    applyWindowAttributes();
}

void NativeWindowAgent::setCornerRadius(int radius) {
    m_cornerRadius = qBound(0, radius, 96);
    applyWindowRegion();
}

void NativeWindowAgent::setShadowAsset(const QUrl &source, int margin, qreal opacity) {
    m_shadowSource = source;
    m_shadowMargin = qBound(0, margin, 128);
    m_shadowOpacity = qBound<qreal>(0.0, opacity, 1.0);
    Q_UNUSED(m_shadowSource)
    Q_UNUSED(m_shadowMargin)
    Q_UNUSED(m_shadowOpacity)
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

bool NativeWindowAgent::eventFilter(QObject *watched, QEvent *event) {
    if (watched == m_window.data() && event) {
        switch (event->type()) {
        case QEvent::Show:
        case QEvent::WindowStateChange:
            applyWindowAttributes();
            break;
        case QEvent::Resize:
            applyWindowRegion(false);
            break;
        default:
            break;
        }
    }
    return QObject::eventFilter(watched, event);
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

void NativeWindowAgent::applyWindowAttributes() {
    if (!m_window)
        return;

#ifdef Q_OS_WIN
    HWND hwnd = reinterpret_cast<HWND>(m_window->winId());
    if (!hwnd)
        return;

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
    // Keep DWM non-client rendering enabled. Disabling it makes Win10
    // draw the classic frame/caption behind the transparent QML chrome.
    const DWORD ncPolicy = 2; // DWMNCRP_ENABLED
    DwmSetWindowAttribute(hwnd, 2, &ncPolicy, sizeof(ncPolicy));

    setWindowAttribute(QStringLiteral("extra-margins"),
                       QVariant::fromValue(QMargins(0, 0, 0, 0)));
    const MARGINS margins = {0, 0, 0, 0};
    DwmExtendFrameIntoClientArea(hwnd, &margins);

    const DWORD doNotRound = 1; // DWMWCP_DONOTROUND
    DwmSetWindowAttribute(hwnd, 33, &doNotRound, sizeof(doNotRound));
    const COLORREF borderNone = 0xFFFFFFFE;
    DwmSetWindowAttribute(hwnd, 34, &borderNone, sizeof(borderNone));
    DwmSetWindowAttribute(hwnd, 35, &borderNone, sizeof(borderNone));

    // Win10/custom-chrome still keeps native caption/thick-frame style bits so QWindowKit can
    // preserve native snap and resize behavior. Clip only the visible HWND shape
    // to avoid exposing the old system frame under QML transparent corners.
    applyWindowRegion();
#else
    Q_UNUSED(m_customShadow)
#endif
}

void NativeWindowAgent::applyWindowRegion(bool redraw) {
#ifdef Q_OS_WIN
    if (!m_window)
        return;
    HWND hwnd = reinterpret_cast<HWND>(m_window->winId());
    if (!hwnd)
        return;

    if (!m_customShadow) {
        clearWindowRegion();
        return;
    }

    const bool square = m_cornerRadius <= 0
                        || m_window->visibility() == QWindow::Maximized
                        || m_window->visibility() == QWindow::FullScreen;

    RECT clientRect = {};
    if (!GetClientRect(hwnd, &clientRect))
        return;
    const int width = clientRect.right - clientRect.left;
    const int height = clientRect.bottom - clientRect.top;
    if (width <= 0 || height <= 0) {
        clearWindowRegion();
        return;
    }

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
#endif
}
void NativeWindowAgent::clearWindowRegion() {
#ifdef Q_OS_WIN
    if (!m_window)
        return;
    HWND hwnd = reinterpret_cast<HWND>(m_window->winId());
    if (hwnd)
        SetWindowRgn(hwnd, nullptr, TRUE);
    m_lastRegionSize = QSize();
    m_lastRegionRadius = -1;
#endif
}

#include "native_window_agent.moc"
