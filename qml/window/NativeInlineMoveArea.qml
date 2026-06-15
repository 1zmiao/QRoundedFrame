import QtQuick
import FramelessNative 1.0
import "../core" as Core

NativeInlineDragArea {
    property var targetItem: null

    anchors.fill: parent
    target: targetItem
    titleBarHeight: Core.Theme.metrics.titleBarHeight
    controlsReserve: Core.Theme.dp(70)
    edgeResizeReserve: Core.Theme.dp(5)
}
