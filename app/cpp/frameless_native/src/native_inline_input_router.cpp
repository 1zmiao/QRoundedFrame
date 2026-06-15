#include "native_inline_input_router.h"

#include <QtCore/QEvent>
#include <QtCore/QMetaObject>
#include <QtCore/QVariant>
#include <QtGui/QMouseEvent>
#include <QtGui/QWheelEvent>
#include <QtQuick/QQuickWindow>

#include <limits>

NativeInlineInputRouter::NativeInlineInputRouter(QQuickItem *parent)
    : QQuickItem(parent) {
    setAcceptedMouseButtons(Qt::NoButton);
    setFlag(QQuickItem::ItemHasContents, false);
    connect(this, &QQuickItem::windowChanged, this, &NativeInlineInputRouter::setObservedWindow);
}

NativeInlineInputRouter::~NativeInlineInputRouter() {
    if (m_observedWindow)
        m_observedWindow->removeEventFilter(this);
}

QQuickItem *NativeInlineInputRouter::manager() const {
    return m_manager;
}

void NativeInlineInputRouter::setManager(QQuickItem *value) {
    if (m_manager == value)
        return;
    m_manager = value;
    emit managerChanged();
}

void NativeInlineInputRouter::setObservedWindow(QQuickWindow *window) {
    if (m_observedWindow == window)
        return;
    if (m_observedWindow)
        m_observedWindow->removeEventFilter(this);
    m_observedWindow = window;
    if (m_observedWindow)
        m_observedWindow->installEventFilter(this);
}

bool NativeInlineInputRouter::eventFilter(QObject *watched, QEvent *event) {
    if (!m_observedWindow || watched != m_observedWindow || !m_manager || !isVisible())
        return false;

    switch (event->type()) {
    case QEvent::MouseButtonPress:
    case QEvent::MouseButtonDblClick: {
        auto *mouseEvent = static_cast<QMouseEvent *>(event);
        raiseInlineWindowAt(mouseEvent->scenePosition());
        break;
    }
    case QEvent::Wheel: {
        auto *wheelEvent = static_cast<QWheelEvent *>(event);
        raiseInlineWindowAt(wheelEvent->position());
        break;
    }
    default:
        break;
    }
    return false;
}

QQuickItem *NativeInlineInputRouter::topInlineWindowAt(const QPointF &scenePoint) const {
    if (!m_observedWindow || !m_observedWindow->contentItem() || !m_manager)
        return nullptr;

    QQuickItem *top = nullptr;
    qreal topZ = -std::numeric_limits<qreal>::infinity();
    const auto children = m_manager->childItems();
    for (auto *item : children) {
        if (!item || item == this || !item->isVisible())
            continue;
        if (!item->property("inlineChildWindow").toBool())
            continue;
        const QPointF localPoint = m_observedWindow->contentItem()->mapToItem(item, scenePoint);
        if (localPoint.x() < 0 || localPoint.x() > item->width())
            continue;
        if (localPoint.y() < 0 || localPoint.y() > item->height())
            continue;
        if (item->z() > topZ) {
            top = item;
            topZ = item->z();
        }
    }
    return top;
}

void NativeInlineInputRouter::raiseInlineWindowAt(const QPointF &scenePoint) {
    auto *top = topInlineWindowAt(scenePoint);
    if (!top)
        return;

    QMetaObject::invokeMethod(
        m_manager,
        "raiseWindow",
        Qt::DirectConnection,
        Q_ARG(QVariant, top->property("pageKey")));
}

#include "native_inline_input_router.moc"
