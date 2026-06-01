#include "external_shadow_controller.h"

#include <QtCore/QByteArray>
#include <QtCore/QCoreApplication>
#include <QtCore/QFileInfo>
#include <QtCore/QTimer>
#include <QtCore/QtGlobal>
#include <QtGui/QGuiApplication>
#include <QtGui/QPainter>
#include <QtGui/QScreen>
#include <QtGui/qrgb.h>

#include <cmath>
#include <cstring>

#ifdef Q_OS_WIN
#    include <dwmapi.h>
#    include <windows.h>
#endif

#ifdef Q_OS_WIN
namespace {
constexpr wchar_t kNativeShadowClassName[] = L"FramelessNativeShadowWindow";

LRESULT CALLBACK nativeShadowWndProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    if (message == WM_NCHITTEST)
        return HTTRANSPARENT;
    return DefWindowProcW(hwnd, message, wParam, lParam);
}

bool ensureNativeShadowClass() {
    static bool registered = false;
    if (registered)
        return true;

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = nativeShadowWndProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = kNativeShadowClassName;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    registered = RegisterClassExW(&wc) || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
    return registered;
}

HBITMAP createDibFromImage(const QImage &source, void **bitsOut) {
    if (source.isNull() || source.width() <= 0 || source.height() <= 0)
        return nullptr;

    QImage image = source.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    BITMAPINFO bmi = {};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = image.width();
    bmi.bmiHeader.biHeight = -image.height();
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;

    void *bits = nullptr;
    HDC screenDc = GetDC(nullptr);
    HBITMAP bitmap = CreateDIBSection(screenDc, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
    ReleaseDC(nullptr, screenDc);
    if (!bitmap || !bits)
        return nullptr;

    const int bytesPerLine = image.width() * 4;
    for (int y = 0; y < image.height(); ++y) {
        memcpy(static_cast<uchar *>(bits) + y * bytesPerLine, image.constScanLine(y), size_t(bytesPerLine));
    }
    if (bitsOut)
        *bitsOut = bits;
    return bitmap;
}
}
#endif

static int alphaAt(const QImage &image, int x, int y) {
    if (x < 0 || y < 0 || x >= image.width() || y >= image.height())
        return 255;
    const auto *line = reinterpret_cast<const QRgb *>(image.constScanLine(y));
    return qAlpha(line[x]);
}

static int shadowBorderOnLine(const QImage &image, bool horizontal) {
    const int length = horizontal ? image.width() : image.height();
    if (length <= 2)
        return 0;
    const int fixed = horizontal ? image.height() / 2 : image.width() / 2;
    constexpr int kVisibleAlpha = 2;

    bool seenVisible = false;
    int leftInner = 0;
    for (int i = 0; i < length; ++i) {
        const int alpha = horizontal ? alphaAt(image, i, fixed) : alphaAt(image, fixed, i);
        if (alpha > kVisibleAlpha) {
            seenVisible = true;
            continue;
        }
        if (seenVisible) {
            leftInner = i;
            break;
        }
    }

    seenVisible = false;
    int rightInner = 0;
    for (int i = length - 1; i >= 0; --i) {
        const int alpha = horizontal ? alphaAt(image, i, fixed) : alphaAt(image, fixed, i);
        if (alpha > kVisibleAlpha) {
            seenVisible = true;
            continue;
        }
        if (seenVisible) {
            rightInner = length - 1 - i;
            break;
        }
    }

    if (leftInner <= 0 || rightInner <= 0 || leftInner + rightInner >= length)
        return 0;
    return qMax(leftInner, rightInner);
}

static int naturalShadowSourceBorder(const QImage &source) {
    if (source.isNull() || source.width() <= 2 || source.height() <= 2)
        return 1;
    const QImage image = source.format() == QImage::Format_ARGB32_Premultiplied
                             ? source
                             : source.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    const int detected = qMax(shadowBorderOnLine(image, true), shadowBorderOnLine(image, false));
    const int fallback = qMax(1, qMin(image.width(), image.height()) / 3);
    const int rawBorder = detected > 0 ? detected : fallback;
    return qBound(1, rawBorder, qMax(1, qMin((image.width() - 1) / 2, (image.height() - 1) / 2)));
}

ExternalShadowController::ExternalShadowController(QObject *parent)
    : QObject(parent)
{
}

ExternalShadowController::~ExternalShadowController() {
    for (auto it = m_nativeShadowByTarget.begin(); it != m_nativeShadowByTarget.end(); ++it)
        destroyNativeShadowState(it.value());
    if (m_nativeEventFilterInstalled && qApp)
        qApp->removeNativeEventFilter(this);
}

void ExternalShadowController::registerShadowWindow(QObject *shadowWindow, QObject *targetWindow, int shadowMargin) {
    QWindow *shadow = asWindow(shadowWindow);
    QWindow *target = asWindow(targetWindow);
    if (!shadow || !target || shadow == target)
        return;
    ensureNativeEventFilter();
    const int margin = qBound(0, shadowMargin, 128);
    const WId targetId = target->winId();
    const QPointer<QWindow> existingShadow = m_shadowByTarget.value(targetId);
    const bool firstRegistration = !existingShadow
                                   || existingShadow.data() != shadow
                                   || m_marginByTarget.value(targetId, -1) != margin;
    m_targetById.insert(targetId, target);
    m_shadowByTarget.insert(targetId, shadow);
    m_marginByTarget.insert(targetId, margin);
    applyShadowWindowStyles(shadow);
    syncShadow(shadow, target, margin, firstRegistration);
}

void ExternalShadowController::stackShadowBehind(QObject *shadowWindow, QObject *targetWindow, int shadowMargin) {
    registerShadowWindow(shadowWindow, targetWindow, shadowMargin);
    QWindow *shadow = asWindow(shadowWindow);
    QWindow *target = asWindow(targetWindow);
    if (shadow && target)
        stackShadow(shadow, target);
}

void ExternalShadowController::stackShadowOnly(QObject *shadowWindow, QObject *targetWindow) {
    QWindow *shadow = asWindow(shadowWindow);
    QWindow *target = asWindow(targetWindow);
    if (!shadow || !target || shadow == target)
        return;
    applyShadowWindowStyles(shadow);
    stackShadow(shadow, target);
}

void ExternalShadowController::syncShadowWindow(QObject *shadowWindow, QObject *targetWindow, int shadowMargin) {
    registerShadowWindow(shadowWindow, targetWindow, shadowMargin);
}

void ExternalShadowController::setNativeShadow(QObject *targetWindow, bool enabled, const QUrl &assetUrl, int shadowMargin, qreal opacity, int cornerRadius) {
    QWindow *target = asWindow(targetWindow);
    if (!target)
        return;
    ensureNativeEventFilter();

    const WId targetId = target->winId();
    NativeShadowState &state = m_nativeShadowByTarget[targetId];
    state.target = target;

    const int nextMargin = qBound(0, shadowMargin, 128);
    const qreal nextOpacity = qBound<qreal>(0.0, opacity, 1.0);
    const int nextCornerRadius = qBound(0, cornerRadius, 128);
    const bool needsRepaint = state.margin != nextMargin
                              || !qFuzzyCompare(state.opacity + 1.0, nextOpacity + 1.0)
                              || state.cornerRadius != nextCornerRadius
                              || state.assetUrl != assetUrl;

    state.enabled = enabled;
    state.margin = nextMargin;
    state.opacity = nextOpacity;
    state.cornerRadius = nextCornerRadius;

    if (!enabled) {
        hideNativeShadow(state);
        return;
    }

    if (!loadNativeShadowAsset(state, assetUrl)) {
        hideNativeShadow(state);
        return;
    }

    syncNativeRegisteredShadow(targetId, true, needsRepaint);
}

void ExternalShadowController::syncNativeShadow(QObject *targetWindow) {
    QWindow *target = asWindow(targetWindow);
    if (!target)
        return;
    syncNativeRegisteredShadow(target->winId(), true, false);
}

void ExternalShadowController::destroyNativeShadow(QObject *targetWindow) {
    QWindow *target = asWindow(targetWindow);
    if (!target)
        return;
    const WId targetId = target->winId();
    auto it = m_nativeShadowByTarget.find(targetId);
    if (it == m_nativeShadowByTarget.end())
        return;
    destroyNativeShadowState(it.value());
    m_nativeShadowByTarget.erase(it);
}

bool ExternalShadowController::isSnapped(QObject *window) const {
    QWindow *target = asWindow(window);
    if (!target)
        return false;
    if (target->visibility() == QWindow::Maximized || target->visibility() == QWindow::FullScreen)
        return false;
    const QRect rect = nativeWindowRect(target);
    const QRect area = nativeWorkAreaForRect(rect);
    return rectLooksSnapped(rect, area);
}

bool ExternalShadowController::nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result) {
    Q_UNUSED(result)
#ifdef Q_OS_WIN
    if (eventType != "windows_generic_MSG" && eventType != "windows_dispatcher_MSG")
        return false;
    MSG *msg = static_cast<MSG *>(message);
    if (!msg || !msg->hwnd)
        return false;
    const WId targetId = reinterpret_cast<WId>(msg->hwnd);
    const bool hasQmlShadow = m_shadowByTarget.contains(targetId);
    const bool hasNativeShadow = m_nativeShadowByTarget.contains(targetId);
    if (!hasQmlShadow && !hasNativeShadow)
        return false;

    switch (msg->message) {
    case WM_DESTROY:
    case WM_NCDESTROY:
        if (hasNativeShadow) {
            auto it = m_nativeShadowByTarget.find(targetId);
            if (it != m_nativeShadowByTarget.end()) {
                destroyNativeShadowState(it.value());
                m_nativeShadowByTarget.erase(it);
            }
        }
        m_shadowByTarget.remove(targetId);
        m_targetById.remove(targetId);
        m_marginByTarget.remove(targetId);
        m_lastShadowGeometryByTarget.remove(targetId);
        break;
    case WM_ENTERSIZEMOVE:
        if (hasNativeShadow) {
            auto it = m_nativeShadowByTarget.find(targetId);
            if (it != m_nativeShadowByTarget.end()) {
                it.value().inSizeMove = true;
                it.value().sizing = false;
            }
        }
        if (hasQmlShadow)
            syncRegisteredShadow(targetId, false);
        if (hasNativeShadow)
            syncNativeRegisteredShadow(targetId, true, false);
        break;
    case WM_SIZING:
        if (hasNativeShadow) {
            auto it = m_nativeShadowByTarget.find(targetId);
            if (it != m_nativeShadowByTarget.end()) {
                it.value().inSizeMove = true;
                it.value().sizing = true;
            }
        }
        break;
    case WM_WINDOWPOSCHANGED:
    case WM_MOVE:
    case WM_SIZE:
        if (hasQmlShadow)
            syncRegisteredShadow(targetId, false);
        if (hasNativeShadow)
            syncNativeRegisteredShadow(targetId, true, msg->message == WM_SIZE);
        break;
    case WM_EXITSIZEMOVE:
        if (hasNativeShadow) {
            auto it = m_nativeShadowByTarget.find(targetId);
            if (it != m_nativeShadowByTarget.end()) {
                it.value().inSizeMove = false;
                it.value().sizing = false;
            }
        }
        if (hasQmlShadow)
            syncRegisteredShadow(targetId, true);
        if (hasNativeShadow)
            syncNativeRegisteredShadow(targetId, true, true);
        break;
    case WM_MOUSEACTIVATE:
    case WM_SETFOCUS:
    case WM_LBUTTONDOWN:
    case WM_NCLBUTTONDOWN:
    case WM_SHOWWINDOW:
    case WM_ACTIVATE:
    case WM_NCACTIVATE:
        if (hasQmlShadow)
            syncRegisteredShadow(targetId, true);
        if (hasNativeShadow)
            syncNativeRegisteredShadow(targetId, true, false);
        break;
    default:
        break;
    }
#endif
    return false;
}

QWindow *ExternalShadowController::asWindow(QObject *object) {
    return qobject_cast<QWindow *>(object);
}

QRect ExternalShadowController::nativeWindowRect(QWindow *window) {
    if (!window)
        return {};
    return window->geometry();
}

QRect ExternalShadowController::nativeTargetRect(QWindow *window) {
    if (!window)
        return {};
#ifdef Q_OS_WIN
    HWND hwnd = reinterpret_cast<HWND>(window->winId());
    if (hwnd) {
        RECT rect = {};
        if (GetWindowRect(hwnd, &rect))
            return QRect(rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top);
    }
#endif
    return window->geometry();
}

int ExternalShadowController::dpiScaled(int value, QWindow *window) {
    if (value <= 0)
        return 0;
#ifdef Q_OS_WIN
    if (window) {
        HWND hwnd = reinterpret_cast<HWND>(window->winId());
        if (hwnd) {
            if (auto getDpiForWindow = reinterpret_cast<UINT(WINAPI *)(HWND)>(
                    GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForWindow"))) {
                return qMax(1, int(std::lround(double(value) * double(getDpiForWindow(hwnd)) / 96.0)));
            }
        }
    }
#endif
    return value;
}

QRect ExternalShadowController::nativeWorkAreaForRect(const QRect &rect) {
    if (!rect.isValid())
        return {};
    QScreen *screen = QGuiApplication::screenAt(rect.center());
    if (!screen)
        screen = QGuiApplication::primaryScreen();
    return screen ? screen->availableGeometry() : QRect();
}

bool ExternalShadowController::rectLooksSnapped(const QRect &rect, const QRect &workArea) {
    if (!rect.isValid() || !workArea.isValid())
        return false;
    const int tol = 12;
    const bool topAligned = qAbs(rect.top() - workArea.top()) <= tol;
    const bool bottomAligned = qAbs(rect.bottom() - workArea.bottom()) <= qMax(tol, 24);
    const bool leftAligned = qAbs(rect.left() - workArea.left()) <= tol;
    const bool rightAligned = qAbs(rect.right() - workArea.right()) <= tol;
    const bool sameHeight = topAligned && bottomAligned;
    if (leftAligned && rightAligned && sameHeight)
        return true;
    const int halfTol = qMax(tol, int(workArea.width() * 0.06));
    const bool halfWidth = qAbs(rect.width() - workArea.width() / 2) <= halfTol;
    const bool leftHalfish = rect.right() <= workArea.left() + int(workArea.width() * 0.75);
    const bool rightHalfish = rect.left() >= workArea.left() + int(workArea.width() * 0.25);
    if (sameHeight && leftAligned && (halfWidth || leftHalfish))
        return true;
    if (sameHeight && rightAligned && (halfWidth || rightHalfish))
        return true;
    return sameHeight;
}

void ExternalShadowController::ensureNativeEventFilter() {
    if (m_nativeEventFilterInstalled || !qApp)
        return;
    qApp->installNativeEventFilter(this);
    m_nativeEventFilterInstalled = true;
}

void ExternalShadowController::syncRegisteredShadow(WId targetId, bool stackBehind) {
    QPointer<QWindow> target = m_targetById.value(targetId);
    QPointer<QWindow> shadow = m_shadowByTarget.value(targetId);
    if (!target || !shadow)
        return;
    syncShadow(shadow, target, m_marginByTarget.value(targetId, 0), stackBehind);
}

void ExternalShadowController::syncNativeRegisteredShadow(WId targetId, bool stackBehind, bool forceRepaint) {
    auto it = m_nativeShadowByTarget.find(targetId);
    if (it == m_nativeShadowByTarget.end())
        return;
    NativeShadowState &state = it.value();
    if (!shouldShowNativeShadow(state)) {
        hideNativeShadow(state);
        return;
    }
    updateNativeShadowBitmap(state, nativeTargetRect(state.target), stackBehind, forceRepaint);
}

void ExternalShadowController::hideNativeShadow(NativeShadowState &state) {
#ifdef Q_OS_WIN
    HWND hwnd = reinterpret_cast<HWND>(state.shadowHwnd);
    if (hwnd && IsWindow(hwnd))
        ShowWindow(hwnd, SW_HIDE);
#endif
    state.shown = false;
    state.openingFadeScheduled = false;
    state.openingOpacityScale = 1.0;
}

void ExternalShadowController::destroyNativeShadowState(NativeShadowState &state) {
#ifdef Q_OS_WIN
    HWND hwnd = reinterpret_cast<HWND>(state.shadowHwnd);
    if (hwnd && IsWindow(hwnd))
        DestroyWindow(hwnd);
#endif
    state.shadowHwnd = 0;
    state.shown = false;
    state.lastBitmapSize = QSize();
    state.lastTargetRect = QRect();
    state.lastShadowRect = QRect();
}

bool ExternalShadowController::ensureNativeShadowWindow(NativeShadowState &state) {
#ifdef Q_OS_WIN
    HWND existing = reinterpret_cast<HWND>(state.shadowHwnd);
    if (existing && IsWindow(existing))
        return true;
    if (!ensureNativeShadowClass())
        return false;

    const DWORD exStyle = WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
    HWND hwnd = CreateWindowExW(exStyle, kNativeShadowClassName, L"", WS_POPUP,
                                0, 0, 1, 1, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    if (!hwnd)
        return false;

    state.shadowHwnd = reinterpret_cast<quintptr>(hwnd);
    state.shown = false;
    return true;
#else
    Q_UNUSED(state)
    return false;
#endif
}

bool ExternalShadowController::loadNativeShadowAsset(NativeShadowState &state, const QUrl &assetUrl) {
    if (state.assetUrl == assetUrl && !state.source.isNull())
        return true;
    state.assetUrl = assetUrl;
    state.source = QImage();
    state.lastBitmapSize = QSize();

    QString path = assetUrl.isLocalFile() ? assetUrl.toLocalFile() : assetUrl.toString(QUrl::PreferLocalFile);
    if (path.startsWith(QStringLiteral("file:///")))
        path = QUrl(path).toLocalFile();
    QImage image(path);
    if (image.isNull())
        return false;
    state.source = image.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    return !state.source.isNull();
}

bool ExternalShadowController::shouldShowNativeShadow(const NativeShadowState &state) const {
    if (!state.enabled || !state.target || state.source.isNull())
        return false;
    if (state.target->visibility() == QWindow::Minimized
        || state.target->visibility() == QWindow::Maximized
        || state.target->visibility() == QWindow::FullScreen)
        return false;
#ifdef Q_OS_WIN
    HWND hwnd = reinterpret_cast<HWND>(state.target->winId());
    if (!hwnd || !IsWindow(hwnd) || !IsWindowVisible(hwnd) || IsIconic(hwnd) || IsZoomed(hwnd))
        return false;
#endif
    const QRect rect = nativeTargetRect(state.target);
    return rect.isValid() && rect.width() > 0 && rect.height() > 0;
}

QImage ExternalShadowController::renderNativeShadowBitmap(const NativeShadowState &state, const QSize &size, int marginPx, int outerPaddingPx, int innerOverlapPx, qreal opacityScale) const {
    if (state.source.isNull() || !size.isValid() || size.width() <= 0 || size.height() <= 0)
        return {};

    QImage result(size, QImage::Format_ARGB32_Premultiplied);
    result.fill(Qt::transparent);

    const QImage source = state.source.format() == QImage::Format_ARGB32_Premultiplied
                              ? state.source
                              : state.source.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    const int srcBorder = naturalShadowSourceBorder(source);
    const int padding = qMax(0, qMin(outerPaddingPx, qMin(size.width() / 4, size.height() / 4)));
    const QRect drawRect(padding, padding, size.width() - padding * 2, size.height() - padding * 2);
    if (!drawRect.isValid() || drawRect.width() <= 0 || drawRect.height() <= 0)
        return result;

    const int overlap = qMax(0, qMin(innerOverlapPx, qMin(drawRect.width() / 4, drawRect.height() / 4)));
    const int dstBorder = qMax(1, qMin(marginPx + overlap, qMin(drawRect.width() / 2, drawRect.height() / 2)));
    const int sw = source.width();
    const int sh = source.height();
    const int dx = drawRect.x();
    const int dy = drawRect.y();
    const int dw = drawRect.width();
    const int dh = drawRect.height();

    const QRect sTopLeft(0, 0, srcBorder, srcBorder);
    const QRect sTop(srcBorder, 0, sw - srcBorder * 2, srcBorder);
    const QRect sTopRight(sw - srcBorder, 0, srcBorder, srcBorder);
    const QRect sLeft(0, srcBorder, srcBorder, sh - srcBorder * 2);
    const QRect sRight(sw - srcBorder, srcBorder, srcBorder, sh - srcBorder * 2);
    const QRect sBottomLeft(0, sh - srcBorder, srcBorder, srcBorder);
    const QRect sBottom(srcBorder, sh - srcBorder, sw - srcBorder * 2, srcBorder);
    const QRect sBottomRight(sw - srcBorder, sh - srcBorder, srcBorder, srcBorder);

    const QRect dTopLeft(dx, dy, dstBorder, dstBorder);
    const QRect dTop(dx + dstBorder, dy, dw - dstBorder * 2, dstBorder);
    const QRect dTopRight(dx + dw - dstBorder, dy, dstBorder, dstBorder);
    const QRect dLeft(dx, dy + dstBorder, dstBorder, dh - dstBorder * 2);
    const QRect dRight(dx + dw - dstBorder, dy + dstBorder, dstBorder, dh - dstBorder * 2);
    const QRect dBottomLeft(dx, dy + dh - dstBorder, dstBorder, dstBorder);
    const QRect dBottom(dx + dstBorder, dy + dh - dstBorder, dw - dstBorder * 2, dstBorder);
    const QRect dBottomRight(dx + dw - dstBorder, dy + dh - dstBorder, dstBorder, dstBorder);

    QPainter painter(&result);
    painter.setRenderHint(QPainter::SmoothPixmapTransform, false);
    painter.setOpacity(qBound<qreal>(0.0, state.opacity * opacityScale, 1.0));
    painter.drawImage(dTopLeft, source, sTopLeft);
    if (dTop.width() > 0)
        painter.drawImage(dTop, source, sTop);
    painter.drawImage(dTopRight, source, sTopRight);
    if (dLeft.height() > 0)
        painter.drawImage(dLeft, source, sLeft);
    if (dRight.height() > 0)
        painter.drawImage(dRight, source, sRight);
    painter.drawImage(dBottomLeft, source, sBottomLeft);
    if (dBottom.width() > 0)
        painter.drawImage(dBottom, source, sBottom);
    painter.drawImage(dBottomRight, source, sBottomRight);
    return result;
}

void ExternalShadowController::updateNativeShadowBitmap(NativeShadowState &state, const QRect &targetRect, bool stackBehind, bool forceRepaint) {
#ifdef Q_OS_WIN
    stackBehind = true;
    if (!targetRect.isValid() || !ensureNativeShadowWindow(state))
        return;
    HWND shadow = reinterpret_cast<HWND>(state.shadowHwnd);
    HWND target = reinterpret_cast<HWND>(state.target ? state.target->winId() : 0);
    if (!shadow || !target || !IsWindow(shadow) || !IsWindow(target))
        return;

    const int marginPx = dpiScaled(state.margin, state.target);
    const int guardPx = dpiScaled(qBound(6, state.margin / 3, 14), state.target);
    const int innerOverlapPx = dpiScaled(qBound(8, state.margin / 2, 24), state.target);
    const int outerPx = marginPx + guardPx;
    const QRect shadowRect = targetRect.adjusted(-outerPx, -outerPx, outerPx, outerPx);
    const bool sizeChanged = state.lastBitmapSize != shadowRect.size();
    const LONG_PTR targetStyle = GetWindowLongPtrW(target, GWL_EXSTYLE);
    const LONG_PTR shadowStyle = GetWindowLongPtrW(shadow, GWL_EXSTYLE);
    const bool targetTopmost = (targetStyle & WS_EX_TOPMOST) != 0;
    const bool shadowTopmost = (shadowStyle & WS_EX_TOPMOST) != 0;
    const UINT baseFlags = SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_NOSENDCHANGING;

    // Idempotency early-out: skip only when geometry, visibility and Z order are
    // already correct. Activation can move the target above other windows without
    // changing geometry; in that case the shadow must still be re-stacked behind
    // the target, otherwise it stays hidden until the next move/resize.
    const bool topmostMatches = targetTopmost == shadowTopmost;
    const bool shadowVisible = IsWindowVisible(shadow);
    const bool stackMatches = !stackBehind || GetWindow(shadow, GW_HWNDPREV) == target;
    if (!forceRepaint && state.shown && shadowVisible && !sizeChanged
        && state.lastShadowRect == shadowRect && topmostMatches && stackMatches)
        return;

    if (!topmostMatches) {
        SetWindowPos(shadow, targetTopmost ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                     baseFlags | SWP_NOMOVE | SWP_NOSIZE | SWP_NOREDRAW);
        stackBehind = true;
    }

    const bool firstVisiblePaint = !state.everShown && !state.shown && !state.inSizeMove && !state.sizing;
    if (firstVisiblePaint)
        state.openingOpacityScale = 0.0;
    const qreal opacityScale = (firstVisiblePaint || state.openingFadeScheduled) ? state.openingOpacityScale : 1.0;

    if (forceRepaint || sizeChanged || !state.shown) {

        const QImage bitmap = renderNativeShadowBitmap(state, shadowRect.size(), marginPx, guardPx, innerOverlapPx, opacityScale);
        if (bitmap.isNull()) {
            hideNativeShadow(state);
            return;
        }
        void *bits = nullptr;
        HBITMAP hBitmap = createDibFromImage(bitmap, &bits);
        if (!hBitmap) {
            hideNativeShadow(state);
            return;
        }

        HDC screenDc = GetDC(nullptr);
        HDC memDc = CreateCompatibleDC(screenDc);
        HGDIOBJ oldBitmap = SelectObject(memDc, hBitmap);
        POINT dst = { shadowRect.x(), shadowRect.y() };
        SIZE size = { shadowRect.width(), shadowRect.height() };
        POINT src = { 0, 0 };
        BLENDFUNCTION blend = { AC_SRC_OVER, 0, 255, AC_SRC_ALPHA };
        UpdateLayeredWindow(shadow, screenDc, &dst, &size, memDc, &src, 0, &blend, ULW_ALPHA);
        SelectObject(memDc, oldBitmap);
        DeleteObject(hBitmap);
        DeleteDC(memDc);
        ReleaseDC(nullptr, screenDc);
        state.lastBitmapSize = shadowRect.size();
    }


    const UINT showFlag = state.shown ? 0 : SWP_SHOWWINDOW;
    SetWindowPos(shadow, stackBehind ? target : nullptr,
                 shadowRect.x(), shadowRect.y(), shadowRect.width(), shadowRect.height(),
                 baseFlags | (stackBehind ? 0 : SWP_NOZORDER) | showFlag);
    state.lastTargetRect = targetRect;
    state.lastShadowRect = shadowRect;
    state.shown = true;
    if (firstVisiblePaint && !state.openingFadeScheduled) {
        state.openingFadeScheduled = true;
        const WId targetId = reinterpret_cast<WId>(target);
        QTimer::singleShot(16, this, [this, targetId]() {
            advanceOpeningFade(targetId, 1);
        });
    } else if (!state.openingFadeScheduled) {
        state.everShown = true;
    }
#else
    Q_UNUSED(state)
    Q_UNUSED(targetRect)
    Q_UNUSED(stackBehind)
    Q_UNUSED(forceRepaint)
#endif
}

void ExternalShadowController::advanceOpeningFade(WId targetId, int step) {
#ifdef Q_OS_WIN
    auto it = m_nativeShadowByTarget.find(targetId);
    if (it == m_nativeShadowByTarget.end())
        return;

    NativeShadowState &state = it.value();
    if (!state.openingFadeScheduled)
        return;
    if (!shouldShowNativeShadow(state)) {
        state.openingFadeScheduled = false;
        state.openingOpacityScale = 1.0;
        return;
    }

    static constexpr int kFadeFrames = 12;
    static constexpr int kFadeFrameMs = 16;
    const int clampedStep = qBound(1, step, kFadeFrames);
    const qreal t = qreal(clampedStep) / qreal(kFadeFrames);
    state.openingOpacityScale = t * t * (3.0 - 2.0 * t);
    syncNativeRegisteredShadow(targetId, true, true);

    if (clampedStep >= kFadeFrames) {
        state.openingFadeScheduled = false;
        state.openingOpacityScale = 1.0;
        state.everShown = true;
        return;
    }

    QTimer::singleShot(kFadeFrameMs, this, [this, targetId, clampedStep]() {
        advanceOpeningFade(targetId, clampedStep + 1);
    });
#else
    Q_UNUSED(targetId)
    Q_UNUSED(step)
#endif
}
void ExternalShadowController::applyShadowWindowStyles(QWindow *shadowWindow) const {
    if (!shadowWindow)
        return;
#ifdef Q_OS_WIN
    HWND hwnd = reinterpret_cast<HWND>(shadowWindow->winId());
    if (!hwnd)
        return;
    const LONG_PTR oldStyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    LONG_PTR style = oldStyle;
    style |= WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
    style &= ~WS_EX_APPWINDOW;
    if (style != oldStyle) {
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE, style);
        SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    }
#endif
}

void ExternalShadowController::syncShadow(QWindow *shadowWindow, QWindow *targetWindow, int shadowMargin, bool stackBehind) {
    if (!shadowWindow || !targetWindow)
        return;
    const int margin = qBound(0, shadowMargin, 128);
    const QRect rect = nativeWindowRect(targetWindow);
    if (!rect.isValid())
        return;
    const QRect shadowRect(rect.x() - margin, rect.y() - margin, rect.width() + margin * 2, rect.height() + margin * 2);
#ifdef Q_OS_WIN
    HWND shadow = reinterpret_cast<HWND>(shadowWindow->winId());
    HWND target = reinterpret_cast<HWND>(targetWindow->winId());
    if (!shadow || !target)
        return;

    const WId targetId = targetWindow->winId();
    if (!stackBehind && m_lastShadowGeometryByTarget.value(targetId) == shadowRect)
        return;

    const LONG_PTR targetStyle = GetWindowLongPtrW(target, GWL_EXSTYLE);
    const LONG_PTR shadowStyle = GetWindowLongPtrW(shadow, GWL_EXSTYLE);
    const bool targetTopmost = (targetStyle & WS_EX_TOPMOST) != 0;
    const bool shadowTopmost = (shadowStyle & WS_EX_TOPMOST) != 0;
    const UINT baseFlags = SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_NOSENDCHANGING;

    if (stackBehind && targetTopmost != shadowTopmost) {
        SetWindowPos(shadow, targetTopmost ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                     baseFlags | SWP_NOMOVE | SWP_NOSIZE | SWP_NOREDRAW);
    }

    SetWindowPos(shadow, stackBehind ? target : nullptr,
                 shadowRect.x(), shadowRect.y(), shadowRect.width(), shadowRect.height(),
                 baseFlags | (stackBehind ? 0 : SWP_NOZORDER));
    m_lastShadowGeometryByTarget.insert(targetId, shadowRect);
#else
    shadowWindow->setGeometry(shadowRect);
    if (stackBehind)
        stackShadow(shadowWindow, targetWindow);
#endif
}

void ExternalShadowController::stackShadow(QWindow *shadowWindow, QWindow *targetWindow) const {
    if (!shadowWindow || !targetWindow)
        return;
#ifdef Q_OS_WIN
    HWND shadow = reinterpret_cast<HWND>(shadowWindow->winId());
    HWND target = reinterpret_cast<HWND>(targetWindow->winId());
    if (!shadow || !target)
        return;
    const LONG_PTR targetStyle = GetWindowLongPtrW(target, GWL_EXSTYLE);
    const LONG_PTR shadowStyle = GetWindowLongPtrW(shadow, GWL_EXSTYLE);
    const bool targetTopmost = (targetStyle & WS_EX_TOPMOST) != 0;
    const bool shadowTopmost = (shadowStyle & WS_EX_TOPMOST) != 0;
    const UINT baseFlags = SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_NOSENDCHANGING;
    if (targetTopmost != shadowTopmost) {
        SetWindowPos(shadow, targetTopmost ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                     baseFlags | SWP_NOREDRAW);
    }
    if (GetWindow(shadow, GW_HWNDPREV) == target)
        return;
    SetWindowPos(shadow, target, 0, 0, 0, 0,
                 baseFlags);
#else
    shadowWindow->lower();
    targetWindow->raise();
#endif
}
#include "external_shadow_controller.moc"

