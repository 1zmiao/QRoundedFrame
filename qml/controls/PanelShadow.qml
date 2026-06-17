import QtQuick
import "../core" as Core

Item {
    id: root
    property int radius: Core.Theme.radius.popup
    property real strength: Core.Theme.mode === "dark" ? 0.36 : 0.20
    property real spreadScale: Math.max(0.82, Math.min(1.35, Math.sqrt(Math.max(1, width * height)) / 255))
    property var layers: [
        { "left": 20, "right": 20, "top": 24, "bottom": 12, "radius": 20, "opacity": 0.038, "soft": true },
        { "left": 16, "right": 16, "top": 19, "bottom": 10, "radius": 16, "opacity": 0.052, "soft": true },
        { "left": 12, "right": 12, "top": 14, "bottom": 8, "radius": 12, "opacity": 0.070, "soft": false },
        { "left": 8, "right": 8, "top": 10, "bottom": 5, "radius": 8, "opacity": 0.085, "soft": false },
        { "left": 5, "right": 5, "top": 6, "bottom": 3, "radius": 5, "opacity": 0.072, "soft": false },
        { "left": 2, "right": 2, "top": 3, "bottom": 1, "radius": 2, "opacity": 0.060, "soft": true }
    ]

    function spread(value) {
        return Core.Theme.dp(value * spreadScale)
    }

    Repeater {
        model: root.layers
        delegate: Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -root.spread(modelData.left)
            anchors.rightMargin: -root.spread(modelData.right)
            anchors.topMargin: -root.spread(modelData.top)
            anchors.bottomMargin: -root.spread(modelData.bottom)
            radius: Math.max(0, root.radius + root.spread(modelData.radius))
            color: modelData.soft ? Core.Theme.color.shadow : Core.Theme.color.menuShadow
            opacity: root.strength * modelData.opacity
        }
    }
}
