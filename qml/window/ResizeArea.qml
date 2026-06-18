import QtQuick
import QtQuick.Window

Item {
    id: root

    property var bridge
    property var windowObject
    property int grip: 6
    property int cornerGrip: 8

    function cursorFor(edge) {
        if (edge === (Qt.LeftEdge | Qt.TopEdge) || edge === (Qt.RightEdge | Qt.BottomEdge))
            return Qt.SizeFDiagCursor
        if (edge === (Qt.RightEdge | Qt.TopEdge) || edge === (Qt.LeftEdge | Qt.BottomEdge))
            return Qt.SizeBDiagCursor
        if (edge === Qt.LeftEdge || edge === Qt.RightEdge)
            return Qt.SizeHorCursor
        if (edge === Qt.TopEdge || edge === Qt.BottomEdge)
            return Qt.SizeVerCursor
        return Qt.ArrowCursor
    }
    function begin(edge) {
        if (bridge && bridge.window && windowObject)
            bridge.window.beginResize(windowObject, edge)
    }
    function update() {
        if (bridge && bridge.window && windowObject)
            bridge.window.updateResize(windowObject)
    }
    function finish() {
        if (bridge && bridge.window && windowObject)
            bridge.window.endResize(windowObject)
    }
    component ResizeHandle: Item {
        property int edgeValue: 0

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: root.cursorFor(edgeValue)
            preventStealing: true
            propagateComposedEvents: false
            onPressed: function(mouse) { mouse.accepted = true; root.begin(edgeValue) }
            onPositionChanged: if (pressed) root.update()
            onReleased: function(mouse) { mouse.accepted = true; root.finish() }
            onCanceled: root.finish()
        }
    }

    // Edges first, corners after them. Later siblings are above earlier ones.
    ResizeHandle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.grip
        edgeValue: Qt.LeftEdge
    }

    ResizeHandle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.grip
        edgeValue: Qt.RightEdge
    }

    ResizeHandle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.grip
        edgeValue: Qt.TopEdge
    }

    ResizeHandle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.grip
        edgeValue: Qt.BottomEdge
    }

    ResizeHandle {
        anchors.left: parent.left
        anchors.top: parent.top
        width: root.cornerGrip
        height: root.cornerGrip
        edgeValue: Qt.LeftEdge | Qt.TopEdge
    }

    ResizeHandle {
        anchors.right: parent.right
        anchors.top: parent.top
        width: root.cornerGrip
        height: root.cornerGrip
        edgeValue: Qt.RightEdge | Qt.TopEdge
    }

    ResizeHandle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: root.cornerGrip
        height: root.cornerGrip
        edgeValue: Qt.LeftEdge | Qt.BottomEdge
    }

    ResizeHandle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: root.cornerGrip
        height: root.cornerGrip
        edgeValue: Qt.RightEdge | Qt.BottomEdge
    }
}
