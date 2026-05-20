import QtQuick
import QtQuick.Window

Item {
    id: root

    property var bridge
    property var windowObject
    property int grip: 5
    property int cornerGrip: 14

    function begin(edge) {
        if (bridge && windowObject)
            bridge.window.beginResize(windowObject, edge)
    }
    function update() {
        if (bridge && windowObject)
            bridge.window.updateResize(windowObject)
    }
    function finish() {
        if (bridge && windowObject)
            bridge.window.endResize(windowObject)
    }

    component ResizeMouseArea: MouseArea {
        property int edgeValue: 0
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        preventStealing: true
        propagateComposedEvents: false
        onPressed: function(mouse) { mouse.accepted = true; root.begin(edgeValue) }
        onPositionChanged: if (pressed) root.update()
        onReleased: function(mouse) { mouse.accepted = true; root.finish() }
        onCanceled: root.finish()
    }

    // Edges first, corners after them. Later siblings are above earlier ones.
    ResizeMouseArea {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.grip
        cursorShape: Qt.SizeHorCursor
        edgeValue: Qt.LeftEdge
    }

    ResizeMouseArea {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.grip
        cursorShape: Qt.SizeHorCursor
        edgeValue: Qt.RightEdge
    }

    ResizeMouseArea {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.grip
        cursorShape: Qt.SizeVerCursor
        edgeValue: Qt.TopEdge
    }

    ResizeMouseArea {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.grip
        cursorShape: Qt.SizeVerCursor
        edgeValue: Qt.BottomEdge
    }

    ResizeMouseArea {
        anchors.left: parent.left
        anchors.top: parent.top
        width: root.cornerGrip
        height: root.cornerGrip
        cursorShape: Qt.SizeFDiagCursor
        edgeValue: Qt.LeftEdge | Qt.TopEdge
    }

    ResizeMouseArea {
        anchors.right: parent.right
        anchors.top: parent.top
        width: root.cornerGrip
        height: root.cornerGrip
        cursorShape: Qt.SizeBDiagCursor
        edgeValue: Qt.RightEdge | Qt.TopEdge
    }

    ResizeMouseArea {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: root.cornerGrip
        height: root.cornerGrip
        cursorShape: Qt.SizeBDiagCursor
        edgeValue: Qt.LeftEdge | Qt.BottomEdge
    }

    ResizeMouseArea {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: root.cornerGrip
        height: root.cornerGrip
        cursorShape: Qt.SizeFDiagCursor
        edgeValue: Qt.RightEdge | Qt.BottomEdge
    }
}
