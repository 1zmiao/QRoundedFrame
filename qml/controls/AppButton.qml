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
    property bool clickOnPress: false

    // Compact API plus backward-compatible names used by older demo files.
    property int minButtonWidth: 0
    property int paddingH: 0
    property int minWidth: Core.Theme.dp(72)
    property int horizontalPadding: Core.Theme.dp(24)
    property int labelPixelSize: Core.Theme.fontSize.control
    property int radius: Core.Theme.radius.button

    signal clicked()

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
        return "transparent"
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.bgColor()
        border.color: root.isFilled || root.isSoft ? Core.Theme.primaryOutline : "transparent"
        border.width: root.isFilled || root.isSoft ? 1 : 0
    }

    Text {
        id: label
        anchors.centerIn: parent
        color: root.isFilled ? Core.Theme.primaryText : Core.Theme.color.text
        font.pixelSize: root.labelPixelSize
        font.bold: root.isFilled || root.active
        elide: Text.ElideRight
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onPressed: if (root.clickOnPress) root.clicked()
        onClicked: if (!root.clickOnPress) root.clicked()
    }
}
