import QtQuick
import QtQuick.Window
import QtQuick.Controls
import FramelessNative 1.0
import "../core" as Core
import "../controls"

Window {
    id: root

    default property alias content: contentHost.data
    property var bridge
    property string windowKey: "window"
    property alias titleBar: titleBarControl
    property alias leftMenus: titleBarControl.leftMenus
    property string shadowPolicy: "auto"
    property string cornerPolicy: "auto"
    property bool alwaysOnTop: false
    property bool showNavToggle: true
    property bool showColorButton: Core.Theme.showColorButton
    property bool autoRestoreWindowState: true
    property bool autoShow: true
    property bool snappedVisual: false
    property bool windowMaximized: visibility === Window.Maximized || visibility === Window.FullScreen
    property string effectiveShadowPolicy: shadowPolicy === "auto"
                                           && root.bridge && root.bridge.window
                                           && root.bridge.window.windowShadowPolicy !== undefined
                                           ? root.bridge.window.windowShadowPolicy
                                           : shadowPolicy
    property string effectiveCornerPolicy: cornerPolicy === "auto"
                                           && root.bridge && root.bridge.window
                                           && root.bridge.window.windowCornerPolicy !== undefined
                                           ? root.bridge.window.windowCornerPolicy
                                           : cornerPolicy
    property bool customExternalShadow: effectiveShadowPolicy === "custom-external"
                                        && root.bridge && root.bridge.window
                                        && root.bridge.window.externalShadowSupported
    property bool nativeExternalShadow: customExternalShadow && Qt.platform.os === "windows"
    property bool qmlExternalShadow: customExternalShadow && !nativeExternalShadow
    property bool nativeShadowDisplayReady: !root.nativeExternalShadow
    property bool customShadowEnabled: customExternalShadow
                                       && root.visible
                                       && root.visibility !== Window.Minimized
                                       && !root.windowMaximized
                                       && !root.snappedVisual
                                       && (!root.nativeExternalShadow || root.nativeShadowDisplayReady)
    property int externalShadowMargin: {
        const metrics = Core.Theme.metrics
        if (metrics && metrics["windowShadowMargin"] !== undefined)
            return Math.max(0, Math.round(metrics["windowShadowMargin"]))
        if (metrics && metrics["shadowMargin"] !== undefined)
            return Math.max(0, Math.round(metrics["shadowMargin"]))
        return Core.Theme.dp(38)
    }
    property real externalShadowOpacity: {
        const metrics = Core.Theme.metrics
        if (Core.Theme.mode === "dark" && metrics && metrics["windowShadowOpacityDark"] !== undefined)
            return Math.max(0, Math.min(1, Number(metrics["windowShadowOpacityDark"])))
        if (Core.Theme.mode !== "dark" && metrics && metrics["windowShadowOpacityLight"] !== undefined)
            return Math.max(0, Math.min(1, Number(metrics["windowShadowOpacityLight"])))
        return Core.Theme.mode === "dark" ? 1.0 : 1.0
    }
    property int normalCornerRadius: Core.Theme.radius.window
    property int cornerRadius: (root.windowMaximized || root.snappedVisual || effectiveCornerPolicy === "square") ? 0 : normalCornerRadius
    property bool _localThemeAnimation: false

    signal windowEvent(string type, var payload)
    signal requestThemeToggle(point localPos, string nextMode)
    signal requestAlwaysOnTop(bool enabled)
    signal navToggleRequested()
    flags: Qt.Window
           | Qt.WindowSystemMenuHint
           | Qt.WindowMinimizeButtonHint
           | Qt.WindowMaximizeButtonHint
           | Qt.WindowCloseButtonHint
           | (root.customExternalShadow ? (Qt.FramelessWindowHint | Qt.NoDropShadowWindowHint) : 0)
    color: "transparent"
    visible: false

    NativeWindowAgent {
        id: nativeAgent
    }

    ExternalShadowController {
        id: externalShadow
    }

    ShadowWindow {
        id: customShadow
        targetWindow: (root.qmlExternalShadow && root.customShadowEnabled) ? root : null
        stackController: externalShadow
        shadowEnabled: root.qmlExternalShadow && root.customShadowEnabled
        shadowMargin: root.externalShadowMargin
        cornerRadius: root.cornerRadius
    }

    function raiseSelf() {
        try { root.raise() } catch (e) {}
        try { root.requestActivate() } catch (e2) {}
    }

    function registerNativeChrome() {
        nativeAgent.setup(root)
        nativeAgent.setCustomShadowEnabled(root.customExternalShadow)
        nativeAgent.setCornerRadius(root.cornerRadius)
        nativeAgent.setShadowAsset(Qt.resolvedUrl("../../resources/images/window_shadow.png"), root.externalShadowMargin,
                                   root.externalShadowOpacity)

        nativeAgent.setTitleBar(titleBarControl)
        nativeAgent.setSystemButton("minimize", titleBarControl.minimizeButtonItem)
        nativeAgent.setSystemButton("maximize", titleBarControl.maximizeButtonItem)
        nativeAgent.setSystemButton("close", titleBarControl.closeButtonItem)

        const clickableItems = [
            titleBarControl.navToggleButtonItem,
            titleBarControl.leftMenusAreaItem,
            titleBarControl.paletteButtonItem,
            titleBarControl.themeButtonItem,
            titleBarControl.pinButtonItem,
            titleBarControl.minimizeButtonItem,
            titleBarControl.maximizeButtonItem,
            titleBarControl.closeButtonItem
        ]
        for (let i = 0; i < clickableItems.length; ++i) {
            if (clickableItems[i])
                nativeAgent.setHitTestVisible(clickableItems[i], true)
        }
    }

    function cleanupExternalShadow() {
        try {
            if (externalShadow && externalShadow.destroyNativeShadow)
                externalShadow.destroyNativeShadow(root)
        } catch (e) {}
        try {
            customShadow.targetWindow = null
            customShadow.shadowEnabled = false
        } catch (e2) {}
    }
    function syncExternalShadow() {
        if (!externalShadow || !externalShadow.setNativeShadow)
            return
        if (root.nativeExternalShadow) {
            externalShadow.setNativeShadow(root, root.customShadowEnabled,
                                           Qt.resolvedUrl("../../resources/images/window_shadow.png"),
                                           root.externalShadowMargin,
                                           root.externalShadowOpacity,
                                           root.cornerRadius)
        } else {
            externalShadow.destroyNativeShadow(root)
        }
    }

    function scheduleNativeShadowShow() {
        if (root.nativeExternalShadow && root.visible && !root.nativeShadowDisplayReady) {
            root.syncExternalShadow()
            initialNativeShadowTimer.restart()
            return
        }
        root.syncExternalShadow()
        stableNativeShadowSyncTimer.restart()
        Qt.callLater(function() {
            root.syncNativeWindowState()
            if (root.nativeExternalShadow && root.customShadowEnabled)
                externalShadow.syncNativeShadow(root)
        })
    }
    function syncNativeWindowState() {
        root.snappedVisual = externalShadow.isSnapped(root)
        root.syncExternalShadow()
    }

    function toggleMaximized() {
        if (root.visibility === Window.Maximized || nativeAgent.isMaximized(root))
            root.showNormal()
        else
            root.showMaximized()
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

    function adjustFontScaleByWheel(deltaY) {
        if (!root.bridge || !root.bridge.theme)
            return
        if (deltaY > 0)
            root.bridge.theme.increaseFontScale()
        else if (deltaY < 0)
            root.bridge.theme.decreaseFontScale()
    }

    function restorePersistedWindowState() {
        if (root.bridge && root.bridge.window && root.bridge.window.restoreNativeManagedWindowState)
            root.bridge.window.restoreNativeManagedWindowState(root)
    }

    function showToast(message) {
        toastModel.append({ "message": message, "createdAt": Date.now() })
        while (toastModel.count > 5)
            toastModel.remove(0)
    }

    WheelHandler {
        acceptedModifiers: Qt.ControlModifier
        target: null
        onWheel: function(event) {
            root.adjustFontScaleByWheel(event.angleDelta.y)
            event.accepted = true
        }
    }

    Item {
        id: frameRoot
        objectName: "appFrameRoot"
        property int visualRadius: root.cornerRadius
        anchors.fill: parent
        clip: true

        Rectangle {
            id: background
            anchors.fill: parent
            radius: root.cornerRadius
            antialiasing: true
            color: Core.Theme.color.surface
            border.color: "transparent"
            border.width: 0
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
                windowTitle: root.title.length > 0 ? root.title : Core.AppInfo.windowTitle
                frameRadius: root.cornerRadius
                alwaysOnTop: root.alwaysOnTop
                showNavToggle: root.showNavToggle
                showColorButton: root.showColorButton
                windowMaximized: root.windowMaximized
                useNativeCaption: true

                onActivateRequested: {
                    root.raiseSelf()
                    if (root.nativeExternalShadow)
                        root.nativeShadowDisplayReady = true
                    if (root.qmlExternalShadow)
                        customShadow.forceStackSync(1)
                    else
                        externalShadow.syncNativeShadow(root)
                }                onToggleMaximizeRequested: root.toggleMaximized()
                onMinimizeRequested: root.showMinimized()
                onCloseRequested: root.close()
                onThemeToggleRequested: function(localPos, nextMode) {
                    root.changeThemeWithRipple(nextMode, localPos.x, localPos.y)
                }
                onAlwaysOnTopRequested: function(enabled) {
                    root.alwaysOnTop = enabled
                    if (root.bridge && root.bridge.window)
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
    }


    Timer {
        id: initialNativeShadowTimer
        interval: 50
        repeat: false
        onTriggered: {
            root.nativeShadowDisplayReady = true
            root.scheduleNativeShadowShow()
        }
    }
    Timer {
        id: stableNativeShadowSyncTimer
        interval: 35
        repeat: false
        onTriggered: {
            root.syncNativeWindowState()
            if (root.nativeExternalShadow && root.customShadowEnabled)
                externalShadow.syncNativeShadow(root)
        }
    }
    Timer {
        id: snapStateSyncTimer
        interval: 0
        repeat: false
        onTriggered: root.syncNativeWindowState()
    }

    Connections {
        target: root.bridge ? root.bridge.theme : null
        function onModeChanged(mode) {
            nativeAgent.setShadowAsset(Qt.resolvedUrl("../../resources/images/window_shadow.png"), root.externalShadowMargin,
                                       root.externalShadowOpacity)
            root.syncExternalShadow()
            if (root._localThemeAnimation) {
                root._localThemeAnimation = false
                return
            }
            transitionLayer.play(frameRoot.width / 2, frameRoot.height / 2, mode)
        }
    }

    Component.onCompleted: {
        root.registerNativeChrome()
        if (root.autoRestoreWindowState)
            root.restorePersistedWindowState()
        if (root.autoShow) {
            root.visible = true
            root.syncNativeWindowState()
            root.scheduleNativeShadowShow()
        }
    }

    Component.onDestruction: root.cleanupExternalShadow()

    onXChanged: { snapStateSyncTimer.restart(); stableNativeShadowSyncTimer.restart() }
    onYChanged: { snapStateSyncTimer.restart(); stableNativeShadowSyncTimer.restart() }
    onWidthChanged: {
        snapStateSyncTimer.restart()
        stableNativeShadowSyncTimer.restart()
        windowEvent("widthChanged", ({ "width": width }))
    }
    onHeightChanged: {
        snapStateSyncTimer.restart()
        stableNativeShadowSyncTimer.restart()
        windowEvent("heightChanged", ({ "height": height }))
    }
    onVisibilityChanged: {
        snapStateSyncTimer.restart()
        windowEvent("visibilityChanged", ({ "visibility": root.visibility }))
        nativeAgent.setCornerRadius(root.cornerRadius)
        root.scheduleNativeShadowShow()
    }
    onVisibleChanged: {
        if (!root.visible)
            root.nativeShadowDisplayReady = !root.nativeExternalShadow
        root.scheduleNativeShadowShow()
    }
    onCornerRadiusChanged: {
        nativeAgent.setCornerRadius(root.cornerRadius)
        root.syncExternalShadow()
    }
    onCustomExternalShadowChanged: {
        nativeAgent.setCustomShadowEnabled(root.customExternalShadow)
        root.syncExternalShadow()
    }
    onCustomShadowEnabledChanged: root.syncExternalShadow()
    onEffectiveShadowPolicyChanged: {
        nativeAgent.setCustomShadowEnabled(root.customExternalShadow)
        root.syncExternalShadow()
    }
    onExternalShadowMarginChanged: {
        nativeAgent.setShadowAsset(Qt.resolvedUrl("../../resources/images/window_shadow.png"), root.externalShadowMargin,
                                   root.externalShadowOpacity)
        root.syncExternalShadow()
    }
    onExternalShadowOpacityChanged: {
        nativeAgent.setShadowAsset(Qt.resolvedUrl("../../resources/images/window_shadow.png"), root.externalShadowMargin,
                                   root.externalShadowOpacity)
        root.syncExternalShadow()
    }
    onActiveChanged: {
        windowEvent("activeChanged", ({ "active": active }))
        if (active && root.nativeExternalShadow) {
            root.nativeShadowDisplayReady = true
            root.syncExternalShadow()
            if (root.customShadowEnabled)
                externalShadow.syncNativeShadow(root)
        }
    }
    onClosing: function(close) {
        if (root.bridge && root.bridge.window && root.bridge.window.saveNativeManagedWindowState)
            root.bridge.window.saveNativeManagedWindowState(root)
        if (root.windowKey === "main" && root.bridge && root.bridge.tray && root.bridge.tray.handleClosing(root)) {
            close.accepted = false
            return
        }
        if (root.windowKey === "main" && root.bridge && root.bridge.dialogs)
            root.bridge.dialogs.closeAll()
        root.cleanupExternalShadow()
        windowEvent("closing", ({}))
    }
}







