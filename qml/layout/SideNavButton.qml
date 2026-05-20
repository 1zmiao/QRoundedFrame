import QtQuick
import "../core" as Core

Item {
    id: root

    property string page: ""
    property string text: ""
    property string iconName: ""
    property bool selected: false
    property bool compact: false

    signal clicked()

    width: parent ? parent.width : 180
    height: 36

    Rectangle {
        anchors.fill: parent
        radius: Core.Theme.radius.button
        color: root.selected ? Core.Theme.color.navActive : (mouse.containsMouse ? Core.Theme.color.controlHover : "transparent")
        border.color: root.selected ? Core.Theme.primaryOutline : "transparent"
        border.width: root.selected ? 1 : 0
    }

    Canvas {
        id: iconCanvas
        x: root.compact ? Math.round((root.width - width) / 2) : 14
        anchors.verticalCenter: parent.verticalCenter
        width: 15
        height: 15
        antialiasing: true
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            Core.Icons.drawIcon(ctx, root.iconName, width, height, root.selected ? Core.Theme.color.navSelectedIcon : Core.Theme.color.icon, 1.05)
        }
        Connections {
            target: Core.Theme
            function onModeChanged() { iconCanvas.requestPaint() }
            function onPrimaryChanged() { iconCanvas.requestPaint() }
        }
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 40
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        visible: !root.compact
        color: root.selected ? Core.Theme.color.navSelectedText : Core.Theme.color.text
        font.pixelSize: Core.Theme.sp(13)
        font.bold: root.selected
        elide: Text.ElideRight
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
