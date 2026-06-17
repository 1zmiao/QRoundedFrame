import QtQuick
import QtQuick.Window

Window {
    id: root
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | Qt.WindowTransparentForInput | Qt.WindowStaysOnTopHint
    color: "transparent"
    visible: false

    property rect targetRect: Qt.rect(0, 0, 0, 0)
    property int previewRadius: 12

    x: targetRect.x
    y: targetRect.y
    width: targetRect.width
    height: targetRect.height

    Rectangle {
        anchors.fill: parent
        anchors.margins: 8
        radius: root.previewRadius
        color: "#26324772"
        border.color: "#6F8EA8B8"
        border.width: 1
    }

    function showAt(r) {
        targetRect = r
        visible = true
        raise()
    }

    function hidePreview() {
        visible = false
    }
}
