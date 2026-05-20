import QtQuick
import QtQuick.Window
import QtQuick.Controls
import "../core" as Core
import "../controls"

Window {
    id: root

    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"
    visible: true

    default property alias content: contentHost.data

    property string windowKey: "window"
    property var bridge
    property alias titleBar: titleBarControl
    property bool alwaysOnTop: false
    property bool shadowEnabled: true
    property bool showNavToggle: true
    property bool showColorButton: Core.Theme.showColorButton
    property int normalCornerRadius: Core.Theme.radius.window
    property int cornerRadius: (visibility === Window.Maximized || visibility === Window.FullScreen) ? 0 : normalCornerRadius
    property bool resizeEnabled: visibility !== Window.Maximized && visibility !== Window.FullScreen
    property bool _localThemeAnimation: false
    property int shadowVisualInset: (cornerRadius > 0 && Qt.platform.os === "windows") ? 1 : 0
    property bool snappedVisual: false

    signal windowEvent(string type, var payload)
    signal requestThemeToggle(point localPos, string nextMode)
    signal requestAlwaysOnTop(bool enabled)
    signal navToggleRequested()

    function raiseSelf() {
        try { root.raise() } catch (e) {}
        try { root.requestActivate() } catch (e2) {}
    }

    function toggleMaximized() {
        if (root.bridge)
            root.bridge.window.toggleMaximized(root)
        else if (visibility === Window.Maximized)
            showNormal()
        else
            showMaximized()
    }

    function showToast(message) {
        toastModel.append({ "message": message, "createdAt": Date.now() })
        while (toastModel.count > 5)
            toastModel.remove(0)
    }

    function changeThemeWithRipple(nextMode, px, py) {
        if (!root.bridge || !root.bridge.theme)
            return
        if (nextMode !== "dark" && nextMode !== "light")
            return
        if (nextMode === Core.Theme.mode)
            return
        const cx = px === undefined ? frameRoot.width / 2 : px
        const cy = py === undefined ? frameRoot.height / 2 : py
        root._localThemeAnimation = true
        if (root.bridge.theme.setRippleOrigin)
            root.bridge.theme.setRippleOrigin(cx, cy)
        transitionLayer.play(cx, cy, nextMode)
        root.bridge.theme.setMode(nextMode)
        root.requestThemeToggle(Qt.point(cx, cy), nextMode)
    }

    Item {
        id: frameRoot
        anchors.fill: parent
        anchors.margins: root.shadowVisualInset
        clip: false

        Rectangle {
            id: background
            antialiasing: true
            anchors.fill: parent
            radius: root.cornerRadius
            color: Core.Theme.color.surface
            border.color: Core.Theme.color.outline
            border.width: (root.cornerRadius === 0 || root.snappedVisual) ? 0 : 1
            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on radius { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }
        }

        ThemeTransitionLayer {
            id: transitionLayer
            anchors.fill: parent
            radius: root.cornerRadius
            z: 1
        }

        Column {
            id: mainColumn
            anchors.fill: parent
            z: 2

            TitleBar {
                id: titleBarControl
                width: parent.width
                height: Core.Theme.metrics.titleBarHeight
                windowTitle: root.title
                frameRadius: root.cornerRadius
                alwaysOnTop: root.alwaysOnTop
                showNavToggle: root.showNavToggle
                showColorButton: root.showColorButton
                windowMaximized: root.visibility === Window.Maximized

                onActivateRequested: {
                    root.raiseSelf()
                    if (root.bridge && root.bridge.window)
                        root.bridge.window.activateWindow(root)
                }

                onMoveRequested: function(localX, localY) {
                    root.raiseSelf()
                    if (root.bridge)
                        root.bridge.window.beginMove(root, localX, localY)
                }
                onMoveUpdated: {
                    if (root.bridge)
                        root.bridge.window.updateMove(root)
                }
                onMoveFinished: {
                    if (root.bridge)
                        root.bridge.window.endMove(root)
                }

                onToggleMaximizeRequested: root.toggleMaximized()
                onMinimizeRequested: root.showMinimized()
                onCloseRequested: root.close()

                onThemeToggleRequested: function(localPos, nextMode) {
                    root.changeThemeWithRipple(nextMode, localPos.x, localPos.y)
                }

                onAlwaysOnTopRequested: function(enabled) {
                    root.alwaysOnTop = enabled
                    if (root.bridge)
                        root.bridge.window.setAlwaysOnTop(root, enabled)
                    root.requestAlwaysOnTop(enabled)
                }

                onToggleNavRequested: root.navToggleRequested()
            }

            Item {
                id: contentHost
                width: parent.width
                height: parent.height - titleBarControl.height
                clip: true
            }
        }


        ListModel { id: toastModel }

        Repeater {
            id: toastRepeater
            model: toastModel
            delegate: Toast {
                z: 1000000
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Core.Theme.dp(22) + index * (Core.Theme.dp(42) + Core.Theme.dp(8))
                height: Core.Theme.dp(42)
                text: model.message
                Component.onCompleted: show(model.message)
                onExpired: {
                    if (index >= 0 && index < toastModel.count)
                        toastModel.remove(index)
                }
            }
        }

        ResizeArea {
            anchors.fill: parent
            enabled: root.resizeEnabled && !(root.bridge && root.bridge.window && root.bridge.window.nativeResize)
            windowObject: root
            bridge: root.bridge
            z: 100
        }
    }

    SnapPreviewWindow { id: snapPreview }

    Timer {
        id: chromeRefreshTimer
        interval: 36
        repeat: false
        onTriggered: if (bridge) bridge.window.refreshNativeFrame(root)
    }

    Connections {
        target: root.bridge ? root.bridge.window : null
        function onSnapPreviewChanged(key, x, y, w, h, visible) {
            if (key !== root.windowKey)
                return
            if (visible)
                snapPreview.showAt(Qt.rect(x, y, w, h))
            else
                snapPreview.hidePreview()
        }
        function onSnappedVisualChanged(key, snapped) {
            if (key === root.windowKey)
                root.snappedVisual = snapped
        }
    }

    Connections {
        target: root.bridge ? root.bridge.theme : null
        function onModeChanged(mode) {
            if (root.bridge)
                chromeRefreshTimer.restart()
            if (root._localThemeAnimation) {
                root._localThemeAnimation = false
                return
            }
            transitionLayer.play(frameRoot.width / 2, frameRoot.height / 2, mode)
        }
        function onPrimaryColorChanged(color) {
            // Pure QML color updates. Avoid native frame refresh while dragging the color wheel.
        }
    }

    Component.onCompleted: {
        if (bridge) {
            bridge.window.restoreWindowState(root)
            bridge.window.installNativeFrame(root)
        }
    }

    onWidthChanged: windowEvent("widthChanged", ({ "width": width }))
    onHeightChanged: windowEvent("heightChanged", ({ "height": height }))
    onVisibilityChanged: {
        chromeRefreshTimer.restart()
        windowEvent("visibilityChanged", ({ "visibility": root.visibility }))
    }
    onActiveChanged: windowEvent("activeChanged", ({ "active": active }))
    onClosing: function(close) {
        if (bridge)
            bridge.window.saveWindowState(root)
        snapPreview.hidePreview()
        if (bridge && bridge.tray && bridge.tray.handleClosing(root)) {
            close.accepted = false
            return
        }
        if (root.windowKey === "main" && bridge && bridge.dialogs)
            bridge.dialogs.closeAll()
        windowEvent("closing", ({}))
    }
}
