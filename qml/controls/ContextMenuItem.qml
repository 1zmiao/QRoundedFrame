import QtQuick
import "../core" as Core

Item {
    id: root

    property string text: ""
    property string shortcut: ""
    property bool available: true
    signal triggered()

    width: parent ? parent.width : 160
    height: Math.max(31, Math.round(Core.Theme.fontSize.control * 2.35))
    opacity: available ? 1.0 : 0.45

    Rectangle {
        anchors.fill: parent
        radius: Core.Theme.radius.button
        color: mouse.containsMouse && root.available ? Core.Theme.color.controlHover : "transparent"
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: Core.Theme.dp(10)
        anchors.right: shortcutText.left
        anchors.rightMargin: Core.Theme.dp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: Core.Theme.color.text
        font.pixelSize: Core.Theme.sp(13)
        elide: Text.ElideRight
    }

    Text {
        id: shortcutText
        anchors.right: parent.right
        anchors.rightMargin: Core.Theme.dp(10)
        anchors.verticalCenter: parent.verticalCenter
        text: root.shortcut
        color: Core.Theme.color.mutedText
        font.pixelSize: Core.Theme.sp(11)
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.available)
                root.triggered()
        }
    }
}
