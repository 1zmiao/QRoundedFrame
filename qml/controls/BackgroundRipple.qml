import QtQuick
import "../core" as Core
import "../window"

Item {
    id: root
    anchors.fill: parent
    enabled: false
    visible: rippleLoader.item ? rippleLoader.item.running : false

    property int radius: Core.Theme.radius.card
    property real startX: width * 0.92
    property real startY: height * 0.08
    property int delayMs: Math.max(0, Math.round((root.x * 0.19 + root.y * 0.13) % 92))
    property real opacityScale: 0.61
    property real renderScale: Core.Theme.lowMemoryMode ? 0.15 : 0.35
    property string colorRole: "card"
    property string pendingMode: ""
    property real pendingX: 0
    property real pendingY: 0
    property bool pendingActivation: false
    property bool diagnosticDisabled: typeof App !== "undefined"
                                      && App
                                      && String(App.envValue("QROUNDEDFRAME_DISABLE_BACKGROUND_RIPPLE")).toLowerCase() === "1"
    property bool lowMemoryVisuals: Core.Theme.lowMemoryMode
                                    && root.Window.window
                                    && root.Window.window.windowKey !== undefined
                                    && String(root.Window.window.windowKey) !== "main"

    function play(px, py, mode) {
        if (root.diagnosticDisabled)
            return
        if (root.lowMemoryVisuals)
            return
        pendingX = px
        pendingY = py
        pendingMode = mode
        if (rippleLoader.item) {
            rippleLoader.item.play(pendingX, pendingY, pendingMode)
        } else if (root.delayMs > 0) {
            pendingActivation = true
            activationDelay.restart()
        } else {
            rippleLoader.active = true
        }
    }

    Timer {
        id: activationDelay
        interval: Math.max(0, root.delayMs)
        repeat: false
        onTriggered: {
            if (root.pendingActivation && root.pendingMode.length > 0)
                rippleLoader.active = true
            root.pendingActivation = false
        }
    }

    Loader {
        id: rippleLoader
        anchors.fill: parent
        active: false
        sourceComponent: ThemeTransitionLayer {
            radius: root.radius
            colorRole: root.colorRole
            startDelay: 0
            opacityScale: root.opacityScale
            renderScale: root.renderScale
            onFinished: {
                root.pendingMode = ""
                root.pendingActivation = false
                rippleLoader.active = false
                if (typeof App !== "undefined" && App && App.trimMemory)
                    Qt.callLater(App.trimMemory)
            }
        }
        onLoaded: {
            if (item && root.pendingMode.length > 0)
                item.play(root.pendingX, root.pendingY, root.pendingMode)
        }
    }

    Connections {
        target: (typeof App !== "undefined" && App && App.theme) ? App.theme : null
        function onModeChanged(mode) {
            root.play(root.startX, root.startY, mode)
        }
    }
}
