import QtQuick
import "../core" as Core

Item {
    id: root

    property alias text: label.text
    property bool hovered: mouseArea.containsMouse
    property bool pressed: mouseArea.pressed
    property bool active: false
    property bool filled: false
    property string variant: "ghost" // ghost | soft | primary
    property bool outlineGhost: false
    property bool clickOnPress: false

    // Compact API plus backward-compatible names used by older demo files.
    property int minButtonWidth: 0
    property int paddingH: 0
    property int minWidth: Core.Theme.dp(72)
    property int horizontalPadding: Core.Theme.dp(24)
    property int labelPixelSize: Core.Theme.fontSize.control
    property int radius: Core.Theme.radius.button
    property int visualTransitionMs: (hovered || pressed) ? Core.Theme.controlTransitionMs : Core.Theme.animatedColorTransitionMs

    signal clicked()
    signal pressStarted()

    implicitWidth: Math.max(
        minButtonWidth > 0 ? minButtonWidth : minWidth,
        label.implicitWidth + ((paddingH > 0 ? paddingH : horizontalPadding) * 2)
    )
    implicitHeight: Core.Theme.metrics.controlHeight
    width: implicitWidth
    height: implicitHeight

    property bool isFilled: filled || variant === "primary"
    property bool isSoft: variant === "soft" || active

    function bgColor() {
        if (isFilled) {
            if (pressed) return Core.Theme.primaryPressed
            if (hovered) return Core.Theme.primaryHover
            return Core.Theme.primary
        }
        if (pressed) return Core.Theme.color.controlPressed
        if (hovered) return Core.Theme.color.controlHover
        if (isSoft) return Core.Theme.primarySoft
        return Core.Theme.alpha(Core.Theme.color.controlHover, 0)
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.bgColor()
        border.color: root.isFilled || root.isSoft
                      ? Core.Theme.primaryOutline
                      : (root.outlineGhost
                         ? (root.hovered || root.pressed
                            ? Core.Theme.color.outlineAccent
                            : Core.Theme.alpha(Core.Theme.color.outline, Core.Theme.mode === "dark" ? 0.72 : 0.62))
                         : Core.Theme.alpha(Core.Theme.primaryOutline, 0))
        border.width: root.isFilled || root.isSoft || root.outlineGhost ? 1 : 0
        Behavior on color { ColorAnimation { duration: root.visualTransitionMs; easing.type: Easing.InOutCubic } }
        Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }

    Text {
        id: label
        anchors.centerIn: parent
        color: root.isFilled ? Core.Theme.primaryText : Core.Theme.color.text
        font.pixelSize: root.labelPixelSize
        font.family: Core.Theme.appFontFamily
        font.bold: root.isFilled || root.active
        elide: Text.ElideRight
        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onPressed: {
            root.pressStarted()
            if (root.clickOnPress)
                root.clicked()
        }
        onClicked: if (!root.clickOnPress) root.clicked()
    }
}
