import QtQuick
import "../core" as Core

Item {
    id: root
    property int radius: Core.Theme.radius.popup
    property real strength: Core.Theme.mode === "dark" ? 0.36 : 0.20

    Rectangle {
        anchors.fill: parent
        anchors.margins: -Core.Theme.dp(8)
        radius: Math.max(0, root.radius + Core.Theme.dp(8))
        color: Core.Theme.color.shadow
        opacity: root.strength * 0.16
    }
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -Core.Theme.dp(5)
        anchors.rightMargin: -Core.Theme.dp(5)
        anchors.topMargin: -Core.Theme.dp(7)
        anchors.bottomMargin: -Core.Theme.dp(3)
        radius: Math.max(0, root.radius + Core.Theme.dp(5))
        color: Core.Theme.color.shadow
        opacity: root.strength * 0.12
    }
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -Core.Theme.dp(2)
        anchors.rightMargin: -Core.Theme.dp(2)
        anchors.topMargin: -Core.Theme.dp(4)
        anchors.bottomMargin: -Core.Theme.dp(1)
        radius: Math.max(0, root.radius + Core.Theme.dp(2))
        color: Core.Theme.color.shadow
        opacity: root.strength * 0.10
    }
}
