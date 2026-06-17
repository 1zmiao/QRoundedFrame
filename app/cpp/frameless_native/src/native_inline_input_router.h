#pragma once

#include <QtCore/QPointer>
#include <QtQml/qqmlregistration.h>
#include <QtQuick/QQuickItem>

class NativeInlineInputRouter : public QQuickItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickItem *manager READ manager WRITE setManager NOTIFY managerChanged)

public:
    explicit NativeInlineInputRouter(QQuickItem *parent = nullptr);
    ~NativeInlineInputRouter() override;

    QQuickItem *manager() const;
    void setManager(QQuickItem *value);

signals:
    void managerChanged();

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void setObservedWindow(QQuickWindow *window);
    QQuickItem *topInlineWindowAt(const QPointF &scenePoint) const;
    void raiseInlineWindowAt(const QPointF &scenePoint);

    QPointer<QQuickItem> m_manager;
    QPointer<QQuickWindow> m_observedWindow;
};
