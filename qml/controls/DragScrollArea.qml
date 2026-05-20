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

    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
}
