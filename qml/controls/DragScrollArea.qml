import QtQuick
import QtQuick.Controls
import "../core" as Core

Flickable {
    id: root
    clip: true
    boundsBehavior: Flickable.DragOverBounds
    contentWidth: width
    contentHeight: Math.max(contentColumn.implicitHeight, contentColumn.childrenRect.y + contentColumn.childrenRect.height) + padding * 2

    default property alias content: contentColumn.data
    property int padding: Core.Theme.metrics.pagePadding
    property alias spacing: contentColumn.spacing

    Column {
        id: contentColumn
        x: root.padding
        y: root.padding
        width: Math.max(1, root.width - root.padding * 2)
        spacing: Core.Theme.dp(14)
    }

    ScrollBar.vertical: ScrollBar {
        id: verticalScrollBar
        policy: ScrollBar.AsNeeded
        width: Core.Theme.dp(11)
        contentItem: Rectangle {
            implicitWidth: Core.Theme.dp(10)
            radius: width / 2
            opacity: (verticalScrollBar.active || verticalScrollBar.hovered || verticalScrollBar.pressed) ? 0.86 : 0
            color: verticalScrollBar.pressed ? Core.Theme.primaryPressed : (verticalScrollBar.hovered ? Core.Theme.primaryHover : Core.Theme.color.outline)
            Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
        }
        background: Item { implicitWidth: Core.Theme.dp(11) }
    }
}