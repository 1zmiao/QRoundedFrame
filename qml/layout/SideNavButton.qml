import QtQuick
import "../core" as Core
import "../controls"

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
        color: root.selected ? Core.Theme.color.navActive : (mouse.containsMouse ? Core.Theme.color.controlHover : Core.Theme.alpha(Core.Theme.color.controlHover, 0))
        border.color: root.selected ? Core.Theme.primaryOutline : Core.Theme.alpha(Core.Theme.primaryOutline, 0)
        border.width: root.selected ? 1 : 0
        Behavior on color { ColorAnimation { duration: root.selected ? Core.Theme.animatedColorTransitionMs : Core.Theme.controlTransitionMs; easing.type: Easing.InOutCubic } }
        Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }

    Rectangle {
        visible: root.selected && !root.compact
        width: Core.Theme.dp(3)
        height: Core.Theme.dp(20)
        radius: width / 2
        anchors.left: parent.left
        anchors.leftMargin: Core.Theme.dp(5)
        anchors.verticalCenter: parent.verticalCenter
        color: Core.Theme.mode === "dark" ? Qt.lighter(Core.Theme.primary, 1.95) : Core.Theme.primary
        opacity: Core.Theme.mode === "dark" ? 1.0 : 0.95
        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
        Behavior on opacity { NumberAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }

    IconImage {
        x: root.compact ? Math.round((parent.width - width) / 2) : Core.Theme.dp(11)
        anchors.verticalCenter: parent.verticalCenter
        width: Core.Theme.dp(15)
        height: width
        iconName: root.iconName
        iconColor: root.selected ? Core.Theme.color.navSelectedIcon : Core.Theme.color.icon
        strokeWidth: 1.05
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: Core.Theme.dp(34)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        visible: !root.compact
        color: root.selected ? Core.Theme.color.navSelectedText : Core.Theme.color.text
        font.pixelSize: Core.Theme.fontSize.control
        font.family: Core.Theme.appFontFamily
        font.bold: root.selected
        elide: Text.ElideRight
        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
