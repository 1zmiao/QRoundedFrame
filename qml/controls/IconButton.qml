import QtQuick
import "../core" as Core

Item {
    id: root

    property string iconName: ""
    property string tooltip: ""
    property bool danger: false
    property bool checkable: false
    property bool checked: false
    property bool interactive: true
    property bool accent: false
    property bool showBorder: true
    property bool noBorder: false
    property bool borderless: false
    property bool flat: false
    property bool forceHovered: false
    property bool hovered: forceHovered || (interactive && mouseArea.containsMouse)
    property bool pressed: interactive && mouseArea.pressed
    property real strokeWidth: 1.05
    property int acceptedButtons: Qt.LeftButton | Qt.RightButton
    property bool clickOnPress: false
    property color iconColor: (checked || accent) ? (Core.Theme.mode === "dark" ? Core.Theme.white : Core.Theme.primaryStrong) : Core.Theme.color.icon
    property int visualTransitionMs: (hovered || pressed) ? Core.Theme.controlTransitionMs : Core.Theme.animatedColorTransitionMs

    signal clicked()
    signal rightClicked(real x, real y)

    width: Core.Theme.metrics.controlHeight
    height: Core.Theme.metrics.controlHeight
    implicitWidth: width
    implicitHeight: height

    function bgColor() {
        if (root.accent && !(root.noBorder || root.borderless || root.flat))
            return pressed ? Core.Theme.primaryPressed : (hovered ? Core.Theme.primaryHover : Core.Theme.primary)
        if (pressed)
            return Core.Theme.color.controlPressed
        if (hovered)
            return Core.Theme.color.controlHover
        if (checked && !(noBorder || borderless || flat))
            return Core.Theme.color.navActive
        return Core.Theme.alpha(Core.Theme.color.controlHover, 0)
    }

    Rectangle {
        anchors.fill: parent
        radius: Core.Theme.radius.button
        color: root.bgColor()
        border.color: (!(root.borderless || root.noBorder || root.flat || !root.showBorder) && root.checked) ? Core.Theme.primaryOutline : Core.Theme.alpha(Core.Theme.primaryOutline, 0)
        border.width: (!(root.borderless || root.noBorder || root.flat || !root.showBorder) && root.checked) ? 1 : 0
        Behavior on color { ColorAnimation { duration: root.visualTransitionMs; easing.type: Easing.InOutCubic } }
        Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }

    IconImage {
        anchors.centerIn: parent
        width: Math.max(14, Math.round(Math.min(root.width, root.height) * (root.iconName === "drag" ? 0.66 : 0.62)))
        height: width
        iconName: root.iconName
        iconColor: root.iconColor
        strokeWidth: root.strokeWidth
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        acceptedButtons: root.acceptedButtons
        onPressed: function(mouse) {
            if (root.clickOnPress && mouse.button === Qt.LeftButton) {
                if (root.checkable)
                    root.checked = !root.checked
                root.clicked()
            }
        }
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                root.rightClicked(mouse.x, mouse.y)
                return
            }
            if (root.clickOnPress)
                return
            if (root.checkable)
                root.checked = !root.checked
            root.clicked()
        }
    }
}
