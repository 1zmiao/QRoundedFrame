import QtQuick
import QtQuick.Window
import "../core" as Core

Window {
    id: root

    objectName: "CustomShadowWindow"
    flags: (Qt.platform.os === "linux" ? Qt.Tool : Qt.Tool)
           | Qt.FramelessWindowHint
           | Qt.WindowDoesNotAcceptFocus
           | Qt.WindowTransparentForInput
           | Qt.NoDropShadowWindowHint
           | (Qt.platform.os === "linux" ? Qt.X11BypassWindowManagerHint : 0)
           | (targetWindow && targetWindow.alwaysOnTop ? Qt.WindowStaysOnTopHint : 0)
    color: "transparent"
    visible: false
    opacity: (root._stackReady && !root._suppressed && !root._holdSuppressed) ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: 0
            easing.type: Easing.OutCubic
        }
    }

    property var targetWindow: null
    property var stackController: null
    property bool shadowEnabled: true
    property int shadowMargin: Core.Theme.dp(38)
    property int shadowSourceBorder: 48
    property int cornerRadius: 10
    property int targetX: valueOf("x", 0)
    property int targetY: valueOf("y", 0)
    property int targetWidth: valueOf("width", 0)
    property int targetHeight: valueOf("height", 0)
    property bool _stackSyncQueued: false
    property int _stackSyncRepeats: 0
    property bool _stackReady: false
    property bool _suppressed: false
    property bool _holdSuppressed: false
    property bool nativeControllerGeometry: false

    function scheduleStackSync() {
        if (_stackSyncQueued)
            return
        _stackSyncQueued = true
        Qt.callLater(function() {
            root._stackSyncQueued = false
            root.syncStack()
            if (root._stackSyncRepeats > 0 && root.visible) {
                root._stackSyncRepeats -= 1
                stackRetryTimer.restart()
            }
        })
    }

    function forceStackSync(repeats) {
        const count = repeats === undefined ? 3 : Math.max(0, repeats)
        root._stackSyncRepeats = Math.max(root._stackSyncRepeats, count)
        scheduleStackSync()
    }

    function suppressFor(ms) {
        root._suppressed = true
        root._stackReady = false
        root.visible = false
        stackShowDelay.interval = Math.max(1, ms === undefined ? 160 : ms)
        stackShowDelay.restart()
    }

    function holdSuppressed() {
        stackShowDelay.stop()
        root._suppressed = false
        root._holdSuppressed = true
        root._stackReady = false
        root.visible = false
    }

    function releaseSuppressed(ms) {
        root._holdSuppressed = false
        suppressFor(ms === undefined ? 90 : ms)
    }

    function cleanup() {
        stackRetryTimer.stop()
        stackShowDelay.stop()
        root._stackSyncQueued = false
        root._stackSyncRepeats = 0
        root._stackReady = false
        root._suppressed = true
        root.visible = false
    }

    function syncStack() {
        if (!targetWindow)
            return
        try {
            if (stackController && stackController.stackShadowOnly) {
                stackController.stackShadowOnly(root, targetWindow)
                root._stackReady = true
                return
            }
            if (stackController && stackController.stackShadowBehind) {
                if (root._stackSyncRepeats > 0) {
                    stackController.stackShadowBehind(root, targetWindow, shadowMargin)
                    root._stackReady = true
                    return
                }
                if (stackController.syncShadowWindow) {
                    stackController.syncShadowWindow(root, targetWindow, shadowMargin)
                    root._stackReady = true
                    return
                }
                if (stackController.registerShadowWindow)
                    stackController.registerShadowWindow(root, targetWindow, shadowMargin)
                stackController.stackShadowBehind(root, targetWindow, shadowMargin)
                root._stackReady = true
                return
            }
        } catch (e) {}
        try { root.lower() } catch (e) {}
        try { if (targetWindow) targetWindow.raise() } catch (e2) {}
        root._stackReady = true
    }

    function syncNativeGeometry() {
        if (!targetWindow || !stackController || !stackController.syncShadowWindow)
            return false
        try {
            stackController.syncShadowWindow(root, targetWindow, shadowMargin)
            root._stackReady = true
            return true
        } catch (e) {
            return false
        }
    }

    function valueOf(name, fallback) {
        if (!targetWindow)
            return fallback
        try {
            const v = targetWindow[name]
            return v === undefined || v === null ? fallback : v
        } catch (e) {
            return fallback
        }
    }

    function boolValue(name, fallback) {
        const v = valueOf(name, fallback)
        return v === undefined || v === null ? fallback : !!v
    }

    function shouldHide() {
        if (!targetWindow || !shadowEnabled)
            return true
        if (_suppressed || _holdSuppressed)
            return true
        if (!boolValue("visible", true))
            return true
        if (valueOf("visibility", Window.Windowed) === Window.Minimized)
            return true
        if (valueOf("visibility", Window.Windowed) === Window.Maximized)
            return true
        if (valueOf("visibility", Window.Windowed) === Window.FullScreen)
            return true
        if (boolValue("maximized", false) || boolValue("snapped", false) || boolValue("snappedVisual", false))
            return true
        return targetWidth <= 0 || targetHeight <= 0
    }

    function syncNow() {
        if (shouldHide()) {
            _stackReady = false
            visible = false
            return
        }
        const nx = targetX - shadowMargin
        const ny = targetY - shadowMargin
        const nw = targetWidth + shadowMargin * 2
        const nh = targetHeight + shadowMargin * 2
        let geometryChanged = false
        if (x !== nx) { x = nx; geometryChanged = true }
        if (y !== ny) { y = ny; geometryChanged = true }
        if (width !== nw) { width = nw; geometryChanged = true }
        if (height !== nh) { height = nh; geometryChanged = true }
        if (!visible) {
            _stackReady = false
            visible = true
            syncStack()
            root._stackSyncRepeats = Math.max(root._stackSyncRepeats, 2)
            scheduleStackSync()
            return
        }
        if (geometryChanged) {
            if (!syncNativeGeometry())
                scheduleStackSync()
            return
        }
        if (!geometryChanged)
            scheduleStackSync()
    }

    Connections {
        target: root.targetWindow
        ignoreUnknownSignals: true
        function onXChanged() { root.syncNow() }
        function onYChanged() { root.syncNow() }
        function onWidthChanged() { root.syncNow() }
        function onHeightChanged() { root.syncNow() }
        function onGeometryChanged() { root.syncNow() }
        function onVisibleChanged() { root.syncNow() }
        function onVisibilityChanged() { root.syncNow() }
        function onActiveChanged() { root.syncNow() }
        function onMaximizedChanged() { root.syncNow() }
        function onSnappedChanged() { root.syncNow() }
        function onSnappedVisualChanged() { root.syncNow() }
        function onAlwaysOnTopChanged() { root.syncNow(); root.forceStackSync(3) }
        function onClosing(close) {
            root.cleanup()
        }
    }

    Timer {
        id: stackRetryTimer
        interval: 35
        repeat: false
        onTriggered: root.scheduleStackSync()
    }

    Timer {
        id: stackShowDelay
        interval: 160
        repeat: false
        onTriggered: {
            root._suppressed = false
            root._holdSuppressed = false
            root.syncNow()
            root.forceStackSync(5)
        }
    }

    BorderImage {
        anchors.fill: parent
        source: "../../resources/images/window_shadow.png"
        border.left: root.shadowSourceBorder
        border.top: root.shadowSourceBorder
        border.right: root.shadowSourceBorder
        border.bottom: root.shadowSourceBorder
        horizontalTileMode: BorderImage.Stretch
        verticalTileMode: BorderImage.Stretch
        smooth: false
        cache: true
        opacity: Core.Theme.mode === "dark" ? 1.0 : 0.7
    }

    Component.onCompleted: syncNow()
    Component.onDestruction: cleanup()
    onTargetWindowChanged: syncNow()
    onTargetXChanged: syncNow()
    onTargetYChanged: syncNow()
    onTargetWidthChanged: syncNow()
    onTargetHeightChanged: syncNow()
    onNativeControllerGeometryChanged: syncNow()
    onShadowMarginChanged: syncNow()
    onShadowEnabledChanged: syncNow()
    onStackControllerChanged: if (visible) scheduleStackSync()
    onVisibleChanged: if (visible) scheduleStackSync()
}

