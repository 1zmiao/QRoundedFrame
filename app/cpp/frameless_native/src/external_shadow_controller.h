#pragma once

#include <QtCore/QHash>
#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QRect>
#include <QtCore/QSize>
#include <QtCore/QUrl>
#include <QtCore/QAbstractNativeEventFilter>
#include <QtGui/QImage>
#include <QtQml/qqmlregistration.h>
#include <QtGui/QWindow>

class ExternalShadowController : public QObject, public QAbstractNativeEventFilter {
    Q_OBJECT
    QML_ELEMENT

public:
    explicit ExternalShadowController(QObject *parent = nullptr);
    ~ExternalShadowController() override;

    Q_INVOKABLE void registerShadowWindow(QObject *shadowWindow, QObject *targetWindow, int shadowMargin = 0);
    Q_INVOKABLE void stackShadowBehind(QObject *shadowWindow, QObject *targetWindow, int shadowMargin = 0);
    Q_INVOKABLE void syncShadowWindow(QObject *shadowWindow, QObject *targetWindow, int shadowMargin);
    Q_INVOKABLE void stackShadowOnly(QObject *shadowWindow, QObject *targetWindow);
    Q_INVOKABLE void setNativeShadow(QObject *targetWindow, bool enabled, const QUrl &assetUrl, int shadowMargin, qreal opacity, int cornerRadius);
    Q_INVOKABLE void syncNativeShadow(QObject *targetWindow);
    Q_INVOKABLE void destroyNativeShadow(QObject *targetWindow);
    Q_INVOKABLE bool isSnapped(QObject *window) const;

    bool nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result) override;

private:
    struct NativeShadowState {
        QPointer<QWindow> target;
        quintptr shadowHwnd = 0;
        QUrl assetUrl;
        QImage source;
        QRect lastTargetRect;
        QRect lastShadowRect;
        QSize lastBitmapSize;
        int margin = 0;
        qreal opacity = 1.0;
        int cornerRadius = 0;
        bool enabled = false;
        bool shown = false;
        bool inSizeMove = false;
        bool sizing = false;
        bool everShown = false;
        bool openingFadeScheduled = false;
        qreal openingOpacityScale = 1.0;
    };

    static QWindow *asWindow(QObject *object);
    static QRect nativeWindowRect(QWindow *window);
    static QRect nativeWorkAreaForRect(const QRect &rect);
    static bool rectLooksSnapped(const QRect &rect, const QRect &workArea);
    void ensureNativeEventFilter();
    void syncRegisteredShadow(WId targetId, bool stackBehind);
    void applyShadowWindowStyles(QWindow *shadowWindow) const;
    void syncShadow(QWindow *shadowWindow, QWindow *targetWindow, int shadowMargin, bool stackBehind);
    void stackShadow(QWindow *shadowWindow, QWindow *targetWindow) const;
    void syncNativeRegisteredShadow(WId targetId, bool stackBehind, bool forceRepaint = false);
    void hideNativeShadow(NativeShadowState &state);
    void destroyNativeShadowState(NativeShadowState &state);
    bool ensureNativeShadowWindow(NativeShadowState &state);
    bool loadNativeShadowAsset(NativeShadowState &state, const QUrl &assetUrl);
    bool shouldShowNativeShadow(const NativeShadowState &state) const;
    QImage renderNativeShadowBitmap(const NativeShadowState &state, const QSize &size, int marginPx, int outerPaddingPx, int innerOverlapPx, qreal opacityScale = 1.0) const;
    void updateNativeShadowBitmap(NativeShadowState &state, const QRect &targetRect, bool stackBehind, bool forceRepaint);
    void advanceOpeningFade(WId targetId, int step);
    static QRect nativeTargetRect(QWindow *window);
    static int dpiScaled(int value, QWindow *window);

    QHash<WId, QPointer<QWindow>> m_targetById;
    QHash<WId, QPointer<QWindow>> m_shadowByTarget;
    QHash<WId, int> m_marginByTarget;
    QHash<WId, QRect> m_lastShadowGeometryByTarget;
    QHash<WId, NativeShadowState> m_nativeShadowByTarget;
    bool m_nativeEventFilterInstalled = false;
};


