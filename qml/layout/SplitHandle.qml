import QtQuick
import "../core" as Core

Rectangle {
    id: root
    width: 6
    color: hover.containsMouse ? Core.Theme.color.controlHover : "transparent"
    signal dragged(real delta)

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.SplitHCursor
    }
}
