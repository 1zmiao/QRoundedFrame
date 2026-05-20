import QtQuick
import "../core" as Core
import "../window"

Item {
    id: root
    anchors.fill: parent
    enabled: false
    visible: ripple.running

    property int radius: Core.Theme.radius.card
    property real startX: width * 0.82
    property real startY: height * 0.18
    property int delayMs: Math.max(0, Math.round((root.x * 0.37 + root.y * 0.23) % 220))
    property real opacityScale: 0.62

    ThemeTransitionLayer {
        id: ripple
        anchors.fill: parent
        radius: root.radius
        startDelay: root.delayMs
        opacityScale: root.opacityScale
    }

    Connections {
        target: (typeof App !== "undefined" && App && App.theme) ? App.theme : null
        function onModeChanged(mode) {
            // Component-level ripples intentionally use their own local origin,
            // so cards/sidebar flow at slightly different positions instead of all
            // expanding from the same point.
            const px = root.startX
            const py = root.startY
            ripple.play(px, py, mode)
        }
    }
}
