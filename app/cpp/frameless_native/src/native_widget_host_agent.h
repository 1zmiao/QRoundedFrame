#pragma once

#include <QtCore/QAbstractNativeEventFilter>
#include <QtCore/QPointF>
#include <QtCore/QPointer>
#include <QtCore/QSize>
#include <QtCore/QVariantMap>
#include <QtGui/QColor>
#include <QtQml/qqmlregistration.h>
#include <QtQuick/QQuickItem>

class NativeWidgetHostAgent : public QQuickItem, public QAbstractNativeEventFilter {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString hostHwnd READ hostHwnd WRITE setHostHwnd NOTIFY hostHwndChanged)
    Q_PROPERTY(bool filterEnabled READ filterEnabled WRITE setFilterEnabled NOTIFY filterEnabledChanged)
    Q_PROPERTY(bool customShadowEnabled READ customShadowEnabled WRITE setCustomShadowEnabled NOTIFY customShadowEnabledChanged)
    Q_PROPERTY(bool maximized READ maximized WRITE setMaximized NOTIFY maximizedChanged)
    Q_PROPERTY(bool fullScreen READ fullScreen WRITE setFullScreen NOTIFY fullScreenChanged)
    Q_PROPERTY(bool snapped READ snapped WRITE setSnapped NOTIFY snappedChanged)
    Q_PROPERTY(qreal resizeBorder READ resizeBorder WRITE setResizeBorder NOTIFY resizeBorderChanged)
    Q_PROPERTY(qreal shadowInset READ shadowInset WRITE setShadowInset NOTIFY shadowInsetChanged)
    Q_PROPERTY(qreal titleBarHeight READ titleBarHeight WRITE setTitleBarHeight NOTIFY titleBarHeightChanged)
    Q_PROPERTY(qreal captionLeftA READ captionLeftA WRITE setCaptionLeftA NOTIFY captionMetricsChanged)
    Q_PROPERTY(qreal captionRightA READ captionRightA WRITE setCaptionRightA NOTIFY captionMetricsChanged)
    Q_PROPERTY(qreal captionLeftB READ captionLeftB WRITE setCaptionLeftB NOTIFY captionMetricsChanged)
    Q_PROPERTY(qreal captionRightB READ captionRightB WRITE setCaptionRightB NOTIFY captionMetricsChanged)
    Q_PROPERTY(QVariantMap minimizeButtonRect READ minimizeButtonRect WRITE setMinimizeButtonRect NOTIFY systemButtonRectsChanged)
    Q_PROPERTY(QVariantMap maximizeButtonRect READ maximizeButtonRect WRITE setMaximizeButtonRect NOTIFY systemButtonRectsChanged)
    Q_PROPERTY(QVariantMap closeButtonRect READ closeButtonRect WRITE setCloseButtonRect NOTIFY systemButtonRectsChanged)

public:
    explicit NativeWidgetHostAgent(QQuickItem *parent = nullptr);
    ~NativeWidgetHostAgent() override;

    QString hostHwnd() const;
    void setHostHwnd(const QString &value);

    bool filterEnabled() const;
    void setFilterEnabled(bool value);

    bool customShadowEnabled() const;
    void setCustomShadowEnabled(bool value);

    bool maximized() const;
    void setMaximized(bool value);

    bool fullScreen() const;
    void setFullScreen(bool value);

    bool snapped() const;
    void setSnapped(bool value);

    qreal resizeBorder() const;
    void setResizeBorder(qreal value);

    qreal shadowInset() const;
    void setShadowInset(qreal value);

    qreal titleBarHeight() const;
    void setTitleBarHeight(qreal value);

    qreal captionLeftA() const;
    void setCaptionLeftA(qreal value);
    qreal captionRightA() const;
    void setCaptionRightA(qreal value);
    qreal captionLeftB() const;
    void setCaptionLeftB(qreal value);
    qreal captionRightB() const;
    void setCaptionRightB(qreal value);
    QVariantMap minimizeButtonRect() const;
    void setMinimizeButtonRect(const QVariantMap &value);
    QVariantMap maximizeButtonRect() const;
    void setMaximizeButtonRect(const QVariantMap &value);
    QVariantMap closeButtonRect() const;
    void setCloseButtonRect(const QVariantMap &value);

    Q_INVOKABLE bool isMaximizedNative() const;
    Q_INVOKABLE bool toggleMaximizedNative();
    Q_INVOKABLE bool showMinimizedNative();
    Q_INVOKABLE bool showMaximizedNative();
    Q_INVOKABLE bool showNormalNative();
    Q_INVOKABLE bool activateNative();
    Q_INVOKABLE bool setTopMostNative(bool enabled, bool activate = false);
    Q_INVOKABLE bool applyWindowsChromeNative();
    Q_INVOKABLE bool beginCaptionMoveNative();
    Q_INVOKABLE bool setMouseCaptureNative(bool enabled);
    Q_INVOKABLE bool setWindowGeometryNative(int x, int y, int width, int height, bool size = true, bool activate = false);
    Q_INVOKABLE QVariantMap windowFrameGeometryNative() const;
    Q_INVOKABLE QVariantMap restoreBoundsNative() const;
    Q_INVOKABLE bool setRestoreBoundsNative(int x, int y, int width, int height);
    Q_INVOKABLE bool forceNormalGeometryNative(int x, int y, int width, int height);
    Q_INVOKABLE void setShellBackgroundColor(const QColor &color);
    Q_INVOKABLE void setCornerRadius(int radius);

signals:
    void hostHwndChanged();
    void filterEnabledChanged();
    void customShadowEnabledChanged();
    void maximizedChanged();
    void fullScreenChanged();
    void snappedChanged();
    void resizeBorderChanged();
    void shadowInsetChanged();
    void titleBarHeightChanged();
    void captionMetricsChanged();
    void systemButtonRectsChanged();
    void sizingOrPositionChanging();
    void moving();
    void nativeSizeMoveStarted();
    void nativeSizeMoveFinished();
    void windowPositionChanged();

protected:
    void componentComplete() override;
    bool nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result) override;

private:
    void installFilter();
    void uninstallFilter();
    quintptr parsedHwnd() const;
    void applyWindowRegion(bool redraw = false);
    void applyWindowRegionForNativeSize(int width, int height, bool redraw = false);
    void clearWindowRegion(bool redraw = true);
    void fillHostWindowBackground();
    int nativeCornerRadiusPx(int radius, quintptr host) const;
    int hitTest(qintptr lparam) const;
    int systemButtonHitTest(qreal localX, qreal localY) const;
    int inferredSystemButtonHitTest(qreal localX, qreal localY) const;
    bool captionHitTest(qreal localX, qreal localY) const;
    void activateWindowBeneathPoint(int x, int y) const;
    QVariantMap sanitizeButtonRect(const QVariantMap &value) const;

    QString m_hostHwnd;
    bool m_filterEnabled = true;
    bool m_customShadowEnabled = false;
    bool m_maximized = false;
    bool m_fullScreen = false;
    bool m_snapped = false;
    bool m_filterInstalled = false;
    qreal m_resizeBorder = 4.0;
    qreal m_shadowInset = 0.0;
    qreal m_titleBarHeight = 36.0;
    qreal m_captionLeftA = 0.0;
    qreal m_captionRightA = 0.0;
    qreal m_captionLeftB = 0.0;
    qreal m_captionRightB = 0.0;
    QVariantMap m_minimizeButtonRect;
    QVariantMap m_maximizeButtonRect;
    QVariantMap m_closeButtonRect;
    QColor m_shellBackgroundColor;
    int m_cornerRadius = 0;
    QSize m_lastRegionSize;
    int m_lastRegionRadius = -1;
    bool m_inNativeSizeMove = false;
};
