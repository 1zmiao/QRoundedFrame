import QtQuick
import QtQuick.Window
import "../core" as Core

Window {
    id: root

    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | Qt.WindowTransparentForInput | Qt.NoDropShadowWindowHint
           | (targetWindow && targetWindow.alwaysOnTop ? Qt.WindowStaysOnTopHint : 0)
    color: "transparent"
    visible: false

    property var targetWindow: null
    property bool shadowEnabled: true
    property int shadowMargin: 48
    property int cornerRadius: 10

    function keepBehindTarget() {
        try { root.lower() } catch (e) {}
        try { if (targetWindow) targetWindow.raise() } catch (e2) {}
    }

    function syncNow() {
        if (!targetWindow || !shadowEnabled || !targetWindow.visible ||
                targetWindow.visibility === Window.Minimized ||
                targetWindow.visibility === Window.Maximized ||
                targetWindow.visibility === Window.FullScreen ||
                targetWindow.width <= 0 || targetWindow.height <= 0) {
            visible = false
            return
        }

        const nx = targetWindow.x - shadowMargin
        const ny = targetWindow.y - shadowMargin
        const nw = targetWindow.width + shadowMargin * 2
        const nh = targetWindow.height + shadowMargin * 2
        if (x !== nx) x = nx
        if (y !== ny) y = ny
        if (width !== nw) width = nw
        if (height !== nh) height = nh
        if (!visible) visible = true
        orderTimer.restart()
    }

    Timer {
        id: orderTimer
        interval: 0
        repeat: false
        onTriggered: root.keepBehindTarget()
    }

    Connections {
        target: root.targetWindow
        function onXChanged() { root.syncNow() }
        function onYChanged() { root.syncNow() }
        function onWidthChanged() { root.syncNow() }
        function onHeightChanged() { root.syncNow() }
        function onVisibleChanged() { root.syncNow() }
        function onVisibilityChanged() { root.syncNow() }
        function onActiveChanged() { root.syncNow() }
    }

    BorderImage {
        anchors.fill: parent
        source: "../assets/window_shadow.png"
        border.left: root.shadowMargin
        border.top: root.shadowMargin
        border.right: root.shadowMargin
        border.bottom: root.shadowMargin
        horizontalTileMode: BorderImage.Stretch
        verticalTileMode: BorderImage.Stretch
        smooth: true
        opacity: Core.Theme.mode === "dark" ? 0.80 : 0.88
    }

    Component.onCompleted: syncNow()
    onTargetWindowChanged: syncNow()
    onShadowMarginChanged: syncNow()
    onShadowEnabledChanged: syncNow()
    onVisibleChanged: if (visible) orderTimer.restart()
}
