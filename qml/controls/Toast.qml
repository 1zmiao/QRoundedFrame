import QtQuick
import "../core" as Core

Item {
    id: root
    property int horizontalMargin: Core.Theme.dp(24)
    property int preferredMinWidth: Core.Theme.dp(128)
    property int preferredMaxWidth: parent ? Math.max(0, parent.width - horizontalMargin * 2) : Core.Theme.dp(520)
    property int contentWidth: label.implicitWidth + Core.Theme.dp(72)

    width: Math.min(preferredMaxWidth, Math.max(Math.min(preferredMinWidth, preferredMaxWidth), contentWidth))
    height: Core.Theme.dp(42)
    opacity: 0
    visible: opacity > 0

    property alias text: label.text
    signal expired()

    Rectangle {
        anchors.fill: parent
        radius: Core.Theme.radius.button
        border.color: Core.Theme.mode === "dark" ? Core.Theme.alpha(Qt.lighter(Core.Theme.primary, 1.95), 0.95) : Core.Theme.color.outlineAccent
        border.width: 1
        color: Core.Theme.mode === "dark" ? Core.Theme.color.cardAlt : Core.Theme.color.card
        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
        Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }

    Text {
        id: label
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Core.Theme.dp(24)
        anchors.rightMargin: Core.Theme.dp(24)
        color: Core.Theme.color.text
        font.pixelSize: Core.Theme.sp(14)
        font.bold: false
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
    }

    Timer {
        id: timer
        interval: 2100
        onTriggered: fadeOut.start()
    }

    NumberAnimation {
        id: fadeOut
        target: root
        property: "opacity"
        from: 1
        to: 0
        duration: 180
        onStopped: {
            if (root.opacity <= 0.01)
                root.expired()
        }
    }

    function show(message) {
        label.text = message
        fadeOut.stop()
        opacity = 1
        timer.restart()
    }
}
