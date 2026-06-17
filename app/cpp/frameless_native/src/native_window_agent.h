#pragma once

#include <QtCore/QEvent>
#include <QtCore/QAbstractNativeEventFilter>
#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QSize>
#include <QtCore/QString>
#include <QtCore/QUrl>
#include <QtGui/QColor>
#include <QtQml/qqmlregistration.h>
#include <QtQuick/QQuickItem>
#include <QtQuick/QQuickWindow>

#include <QWKQuick/quickwindowagent.h>

class NativeWindowAgent : public QWK::QuickWindowAgent, public QAbstractNativeEventFilter {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool nativeSizeMoveActive READ nativeSizeMoveActive NOTIFY nativeSizeMoveActiveChanged)
    Q_PROPERTY(bool nativeSystemMoveActive READ nativeSystemMoveActive NOTIFY nativeSystemMoveActiveChanged)
    Q_PROPERTY(bool nativeSystemMoveFromMaximized READ nativeSystemMoveFromMaximized NOTIFY nativeSystemMoveActiveChanged)
    Q_PROPERTY(qreal effectiveDevicePixelRatio READ effectiveDevicePixelRatio NOTIFY effectiveDevicePixelRatioChanged)

public:
    explicit NativeWindowAgent(QObject *parent = nullptr);
    ~NativeWindowAgent() override;

    Q_INVOKABLE void setup(QQuickWindow *window);
    Q_INVOKABLE void teardown();
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    Q_INVOKABLE void setClientSideShadowMode(bool enabled);
#endif
    Q_INVOKABLE void setTitleBar(QQuickItem *item);
    Q_INVOKABLE void setSystemButton(const QString &role, QQuickItem *item);
    Q_INVOKABLE void setHitTestVisible(QQuickItem *item, bool visible);
    Q_INVOKABLE void setCustomShadowEnabled(bool enabled);
    Q_INVOKABLE void setCornerRadius(int radius);
    Q_INVOKABLE void setShadowAsset(const QUrl &source, int margin, qreal opacity);
    Q_INVOKABLE void setShellBackgroundColor(const QColor &color);
    Q_INVOKABLE void setResizeHitTestInsets(int edgeInset, int cornerInset);
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    Q_INVOKABLE void setGtkFrameExtents(int left, int top, int right, int bottom);
#endif
    Q_INVOKABLE qreal effectiveDevicePixelRatio() const;
    Q_INVOKABLE void setFastExitOnClose(bool enabled);
    Q_INVOKABLE bool isMaximized(QQuickWindow *window) const;
    Q_INVOKABLE void toggleMaximized(QQuickWindow *window);
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    Q_INVOKABLE bool startSystemMove(QQuickWindow *window, int shadowInset = 38);
#endif
    bool nativeSizeMoveActive() const;
    bool nativeSystemMoveActive() const;
    bool nativeSystemMoveFromMaximized() const;

signals:
    void nativeSizeMoveActiveChanged();
    void nativeSystemMoveActiveChanged();
    void nativeSystemButtonHoverChanged(const QString &role);
    void nativeSystemMoveFinished();
    void effectiveDevicePixelRatioChanged();

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;
    bool nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result) override;

private:
    static int systemButtonRole(const QString &role);
    void applyWindowAttributes();
    void applyWindowRegion(bool redraw = true);
    void applyWindowRegionForNativeSize(int width, int height, bool redraw = false);
    void clearWindowRegion();
    void fillWindowBackground();
    void installNativeShellFilter();
    void uninstallNativeShellFilter();
    void updateClassBackgroundBrush();
    void restoreClassBackgroundBrush();
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    void applyClientSideShadowInputRegion();
    void refreshScreenConnections();
    void installX11RootPropertyListener();
    void installKdeScaleWatcher();
    void refreshKdeScaleWatcherPaths();
    void refreshNativeMetrics(const char *reason = "refresh");
    void traceNativeMetrics(const char *reason) const;
#endif
    int nativeSystemButtonHitTest(qintptr lParam) const;
    bool nativeItemContainsScreenPoint(QQuickItem *item, qintptr lParam) const;
    bool nativeItemContainsScreenPoint(QQuickItem *item, qintptr lParam, bool extendToTitleBarHeight) const;
    QString systemButtonRoleForHit(int hit) const;
    void setNativeSystemButtonHover(int hit);
    QColor shellBackgroundColor() const;
    void setNativeSizeMoveActive(bool active);

    QPointer<QQuickWindow> m_window;
    QPointer<QQuickItem> m_titleBarItem;
    QPointer<QQuickItem> m_minimizeButton;
    QPointer<QQuickItem> m_maximizeButton;
    QPointer<QQuickItem> m_closeButton;
    bool m_customShadow = false;
    bool m_nativeShellFilterInstalled = false;
    quintptr m_backgroundBrush = 0;
    quintptr m_previousClassBackgroundBrush = 0;
    int m_cornerRadius = 0;
    QSize m_lastRegionSize;
    int m_lastRegionRadius = -1;
    bool m_inNativeSizeMove = false;
    int m_resizeEdgeInset = 6;
    int m_resizeCornerInset = 8;
    int m_pressedNativeButtonHit = 0;
    int m_hoveredNativeButtonHit = 0;
    bool m_fastExitOnClose = false;
    QColor m_shellBackgroundColor;
    QUrl m_shadowSource;
    int m_shadowMargin = 0;
    qreal m_shadowOpacity = 1.0;
    void *m_hwnd = nullptr;
#if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
    QPointer<QScreen> m_screen;
    bool m_clientSideShadowMode = false;
    QMargins m_gtkFrameExtents;
    int m_linuxCsdFullInset = 0;
    bool m_linuxSystemMoveActive = false;
    bool m_linuxSystemMoveFromMaximized = false;
    bool m_linuxSystemMoveExtentsLocked = false;
    bool m_x11RootPropertyListenerInstalled = false;
    QObject *m_kdeScaleWatcher = nullptr;
    QString m_kdeConfigDir;
    QString m_kdeGlobalsPath;
    QString m_kcmFontsPath;
    qreal m_lastNativeDpr = 0.0;
    qreal m_x11ResourceDpr = 0.0;
#endif
};
