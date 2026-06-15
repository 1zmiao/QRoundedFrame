#pragma once

#include <QtCore/QPointer>
#include <QtCore/QVariant>
#include <QtQml/qqmlregistration.h>
#include <QtQuick/QQuickItem>

class QQuickWindow;

class NativeInlineDragArea : public QQuickItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickItem *target READ target WRITE setTarget NOTIFY targetChanged)
    Q_PROPERTY(qreal titleBarHeight READ titleBarHeight WRITE setTitleBarHeight NOTIFY titleBarHeightChanged)
    Q_PROPERTY(qreal controlsReserve READ controlsReserve WRITE setControlsReserve NOTIFY controlsReserveChanged)
    Q_PROPERTY(qreal edgeResizeReserve READ edgeResizeReserve WRITE setEdgeResizeReserve NOTIFY edgeResizeReserveChanged)

public:
    explicit NativeInlineDragArea(QQuickItem *parent = nullptr);
    ~NativeInlineDragArea() override;

    QQuickItem *target() const;
    void setTarget(QQuickItem *value);

    qreal titleBarHeight() const;
    void setTitleBarHeight(qreal value);

    qreal controlsReserve() const;
    void setControlsReserve(qreal value);

    qreal edgeResizeReserve() const;
    void setEdgeResizeReserve(qreal value);

signals:
    void targetChanged();
    void titleBarHeightChanged();
    void controlsReserveChanged();
    void edgeResizeReserveChanged();
    void dragStarted();
    void clicked();
    void targetClicked(const QVariant &pageKey);

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void mouseUngrabEvent() override;

private:
    void setObservedWindow(QQuickWindow *window);
    QPointF itemPointFromScene(const QPointF &scenePoint) const;
    QQuickItem *topWindowAt(const QPointF &point) const;
    QQuickItem *pressTargetAt(const QPointF &scenePoint) const;
    QPointF parentPointFromScene(const QPointF &scenePoint) const;
    void beginMove(QQuickItem *target, const QPointF &scenePoint);
    void updateMove(const QPointF &scenePoint);
    void finishMoveFromRelease(QMouseEvent *event);
    void endMove(bool releaseGrab = true);

    QPointer<QQuickItem> m_configuredTarget;
    QPointer<QQuickItem> m_target;
    QPointer<QQuickWindow> m_observedWindow;
    QPointF m_pressParentPoint;
    QPointF m_startPosition;
    bool m_moved = false;
    qreal m_titleBarHeight = 36.0;
    qreal m_controlsReserve = 70.0;
    qreal m_edgeResizeReserve = 8.0;
};
