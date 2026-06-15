import QtQuick
import "../core" as Core

Item {
    id: root

    property string text: ""
    property string shortcut: ""
    property string iconName: ""
    property bool available: true
    signal prepared()
    signal triggered()

    width: parent ? parent.width : 160
    height: Math.max(31, Math.round(Core.Theme.fontSize.control * 2.35))
    opacity: available ? 1.0 : 0.45

    Rectangle {
        anchors.fill: parent
        radius: Core.Theme.radius.button
        color: mouse.containsMouse && root.available ? Core.Theme.color.controlHover : Core.Theme.alpha(Core.Theme.color.controlHover, 0)
    }

    IconImage {
        id: icon
        x: Core.Theme.dp(10)
        anchors.verticalCenter: parent.verticalCenter
        width: Core.Theme.dp(16)
        height: Core.Theme.dp(16)
        visible: root.iconName.length > 0
        iconName: root.iconName
        iconColor: Core.Theme.color.icon
        strokeWidth: 1.02
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: root.iconName.length > 0 ? Core.Theme.dp(36) : Core.Theme.dp(10)
        anchors.right: shortcutText.left
        anchors.rightMargin: Core.Theme.dp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: Core.Theme.color.text
        font.pixelSize: Core.Theme.fontSize.control
        elide: Text.ElideRight
    }

    Text {
        id: shortcutText
        anchors.right: parent.right
        anchors.rightMargin: Core.Theme.dp(10)
        anchors.verticalCenter: parent.verticalCenter
        text: root.shortcut
        color: Core.Theme.color.mutedText
        font.pixelSize: Core.Theme.fontSize.tiny
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onEntered: if (root.available) root.prepared()
        onPressed: if (root.available) root.prepared()
        onClicked: {
            if (root.available)
                root.triggered()
        }
    }
}
