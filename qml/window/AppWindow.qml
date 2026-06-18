import QtQuick
import QtQuick.Window
import QtQuick.Controls
import FramelessNative 1.0
import "../core" as Core
import "../controls"

Window {
    id: root

    readonly property real devicePixelRatio: Math.max(1.0, nativeAgent
                                                      ? nativeAgent.effectiveDevicePixelRatio
                                                      : ((root.screen ? root.screen.devicePixelRatio : Screen.devicePixelRatio)))
    readonly property real physicalPixel: 1.0 / devicePixelRatio
    readonly property real stableHairline: Math.max(1.0, physicalPixel)
    function snapToPhysicalPixel(value) {
        return Math.round(value / physicalPixel) * physicalPixel
    }

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
    property bool showThemeButton: true
    property bool showPinButton: true
    property bool lowMemoryVisuals: root.windowKey !== "main"
    property bool autoRestoreWindowState: true
    property bool autoShow: true
    property bool snappedVisual: false
    property bool nativeChromeRegistered: false
    property bool windowMaximized: false
    readonly property bool nativeSizeMoveActive: nativeAgent.nativeSizeMoveActive
    property bool destroyOnChildClose: false
    property bool _destroyingChildWindow: false
    property bool _closingMainWindow: false
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
                                        && !root.nativeShadowDisabledForDiagnostics()
    property bool nativeClippedCustomShell: customExternalShadow && Qt.platform.os === "windows"
    property bool linuxCsdShadow: customExternalShadow
                                  && Qt.platform.os === "linux"
                                  && !linuxCsdController.linuxCsdShadowDisabled()
    property bool nativeExternalShadow: customExternalShadow && Qt.platform.os === "windows"
    property bool qmlExternalShadow: customExternalShadow
                                     && Qt.platform.os !== "linux"
                                     && !nativeExternalShadow
                                     && !linuxCsdShadow
    property bool nativeShadowDisplayReady: false
    property bool customShadowEnabled: customExternalShadow
                                        && root.nativeShadowDisplayReady
                                        && root.visible
                                        && root.visibility !== Window.Minimized
                                        && !root.windowMaximized
                                        && !root.snappedVisual
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
    property bool csdShadowVisible: linuxCsdController.shadowVisible
    property int shadowVisualInset: linuxCsdController.shadowInset
    property int windowStateGeometryInset: linuxCsdController.windowStateGeometryInset
    property int normalCornerRadius: Core.Theme.radius.window
    property int cornerRadius: (root.windowMaximized || root.snappedVisual || effectiveCornerPolicy === "square") ? 0 : normalCornerRadius
    property bool _localThemeAnimation: false
    property bool _childCloseScheduled: false
    property string pendingTransitionMode: ""
    property real pendingTransitionX: 0
    property real pendingTransitionY: 0
    property bool transitionLayerPreloaded: false
    property bool firstFrameReady: false
    property bool firstFrameOpacityGate: root.windowKey === "main" && Qt.platform.os === "windows"

    signal windowEvent(string type, var payload)
    signal requestThemeToggle(point localPos, string nextMode)
    signal requestAlwaysOnTop(bool enabled)
    signal navToggleRequested()
    flags: Qt.Window
           | Qt.FramelessWindowHint
           | (root.customExternalShadow ? Qt.NoDropShadowWindowHint : 0)
           | Qt.WindowSystemMenuHint
           | Qt.WindowMinimizeButtonHint
           | Qt.WindowMaximizeButtonHint
           | Qt.WindowCloseButtonHint
    color: Qt.platform.os === "linux" ? linuxCsdController.shellBackgroundForWindow : Core.Theme.color.surface
    visible: false
    opacity: root.firstFrameOpacityGate && !root.firstFrameReady ? 0 : 1

    Component.onCompleted: {
        if (root.bridge && root.bridge.logRuntime)
            root.bridge.logRuntime("app window chrome key=" + root.windowKey
                                   + " shadowPolicy=" + root.effectiveShadowPolicy
                                   + " nativeExternalShadow=" + root.nativeExternalShadow
                                   + " qmlExternalShadow=" + root.qmlExternalShadow)
        root.registerNativeChrome()
        if (root.windowKey === "main" && root.bridge && root.bridge.registerMainWindow)
            root.bridge.registerMainWindow(root)
        if (root.autoRestoreWindowState)
            root.restorePersistedWindowState()
        if (root.autoShow) {
            root.visible = true
            root.syncNativeWindowState()
        }
    }

    NativeWindowAgent {
        id: nativeAgent
        onNativeSystemButtonHoverChanged: function(role) {
            titleBarControl.minimizeButtonNativeHovered = role === "minimize"
            titleBarControl.maximizeButtonNativeHovered = role === "maximize"
            titleBarControl.closeButtonNativeHovered = role === "close"
        }
    }

    ExternalShadowController {
        id: externalShadow
    }

    LinuxCsdController {
        id: linuxCsdController
        windowRoot: root
        nativeAgent: nativeAgent
        enabled: root.linuxCsdShadow
        windowMaximized: root.windowMaximized
        snappedVisual: root.snappedVisual
        externalShadowMargin: root.externalShadowMargin
        cornerRadius: root.cornerRadius
        surfaceColor: Core.Theme.color.surface
        physicalPixel: root.physicalPixel
    }

    Loader {
        id: customShadowLoader
        active: root.qmlExternalShadow
        sourceComponent: ShadowWindow {
            targetWindow: (root.qmlExternalShadow && root.customShadowEnabled) ? root : null
            stackController: externalShadow
            shadowEnabled: root.qmlExternalShadow && root.customShadowEnabled
            shadowMargin: root.externalShadowMargin
            cornerRadius: root.cornerRadius
        }
    }

    function raiseSelf() {
        try { root.raise() } catch (e) {}
        try { root.requestActivate() } catch (e2) {}
    }

    function registerNativeChrome() {
        linuxCsdController.preRegisterNativeChrome()
        nativeAgent.setup(root)
        linuxCsdController.syncNativeShellBackground()
        root.syncNativeFastExitPolicy()
        root.nativeChromeRegistered = true
        nativeAgent.setCustomShadowEnabled(root.customExternalShadow)
        nativeAgent.setCornerRadius(root.cornerRadius)
        nativeAgent.setShadowAsset(Qt.resolvedUrl("../../resources/images/window_shadow.png"), root.externalShadowMargin,
                                   root.externalShadowOpacity)
        nativeAgent.setResizeHitTestInsets(Core.Theme.metrics.resizeEdgeInset,
                                           Core.Theme.metrics.resizeCornerInset)
        linuxCsdController.postRegisterNativeChrome()

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

    function syncNativeFastExitPolicy() {
        // 主窗口不能走 native fast-exit。否则标题栏关闭按钮会绕过 QML
        // onClosing/requestMainClose，窗口位置、大小、托盘策略都来不及保存。
        nativeAgent.setFastExitOnClose(false)
    }

    function nativeShadowDisabledForDiagnostics() {
        if (typeof App === "undefined" || !App || !App.envValue)
            return false
        const value = String(App.envValue("QROUNDEDFRAME_DISABLE_NATIVE_SHADOW") || "").toLowerCase()
        return value === "1" || value === "true" || value === "yes" || value === "on"
    }

    function registerNativeClickableItem(item) {
        if (root.nativeChromeRegistered && item)
            nativeAgent.setHitTestVisible(item, true)
    }

    function qmlShadowWindow() {
        return customShadowLoader.active ? customShadowLoader.item : null
    }

    function unregisterNativeClickableItem(item) {
        if (root.nativeChromeRegistered && item)
            nativeAgent.setHitTestVisible(item, false)
    }

    function cleanupExternalShadow() {
        try {
            if (externalShadow && externalShadow.destroyNativeShadow)
                externalShadow.destroyNativeShadow(root)
        } catch (e) {}
        try {
            const shadow = root.qmlShadowWindow()
            if (shadow) {
                shadow.targetWindow = null
                shadow.shadowEnabled = false
            }
        } catch (e2) {}
    }

    function fadeOutExternalShadow() {
        if (!root.nativeExternalShadow || !externalShadow || !externalShadow.fadeOutNativeShadow)
            return
        externalShadow.fadeOutNativeShadow(root)
    }

    function finalizeChildClose() {
        if (root._childCloseScheduled)
            return
        root._childCloseScheduled = true
        Qt.callLater(function() {
            root._destroyingChildWindow = true
            stableNativeShadowSyncTimer.stop()
            snapStateSyncTimer.stop()
            resizeTrimTimer.stop()
            if (root.bridge && root.bridge.window && root.bridge.window.saveNativeManagedWindowState)
                root.bridge.window.saveNativeManagedWindowState(root)
            root.visible = false
            root.cleanupExternalShadow()
            if (root.releaseContent)
                root.releaseContent()
            if (root.destroyOnChildClose && nativeAgent.teardown)
                nativeAgent.teardown()
            else
                root.releaseResources()
            root.windowEvent("closing", ({ "destroy": root.destroyOnChildClose }))
        })
    }

    function requestCloseFromController() {
        if (root.windowKey.indexOf("child-") === 0) {
            root.finalizeChildClose()
            return
        }
        root.close()
    }
    function syncExternalShadow() {
        if (root._destroyingChildWindow)
            return
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
        if (root._destroyingChildWindow)
            return
        root.syncExternalShadow()
        stableNativeShadowSyncTimer.restart()
        Qt.callLater(function() {
            root.syncNativeWindowState()
            if (root.nativeExternalShadow && root.customShadowEnabled)
                externalShadow.syncNativeShadow(root)
        })
    }
    function markNativeShadowDisplayReady() {
        if (root._destroyingChildWindow)
            return
        if (!root.visible || root.nativeShadowDisplayReady)
            return
        root.nativeShadowDisplayReady = true
        root.scheduleNativeShadowShow()
    }
    function syncNativeWindowState() {
        if (root._destroyingChildWindow || root._closingMainWindow)
            return
        root.windowMaximized = root.visibility === Window.Maximized
                               || root.visibility === Window.FullScreen
                               || nativeAgent.isMaximized(root)
        root.snappedVisual = root.bridge && root.bridge.window && root.bridge.window.isSnappedState
                             ? root.bridge.window.isSnappedState(root)
                             : externalShadow.isSnapped(root)
        linuxCsdController.applyShadowInset()
        root.syncExternalShadow()
    }

    function toggleMaximized() {
        const wasMaximized = root.visibility === Window.Maximized
                             || root.visibility === Window.FullScreen
                             || nativeAgent.isMaximized(root)
        const wasSnapped = root.bridge && root.bridge.window && root.bridge.window.isSnappedState
                           ? root.bridge.window.isSnappedState(root)
                           : externalShadow.isSnapped(root)
        if (!wasMaximized && !wasSnapped)
            root.fadeOutExternalShadow()
        if (Qt.platform.os === "windows") {
            root.windowMaximized = !wasMaximized
            root.nativeShadowDisplayReady = wasSnapped || !root.windowMaximized
            nativeAgent.setCornerRadius(root.cornerRadius)
            nativeAgent.toggleMaximized(root)
        } else {
            linuxCsdController.handleToggleMaximized(wasMaximized)
        }
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
        if (!root.lowMemoryVisuals && root.bridge && root.bridge.beginVisualTransition)
            root.bridge.beginVisualTransition()
        root._localThemeAnimation = true
        if (root.bridge.theme.setRippleOrigin)
            root.bridge.theme.setRippleOrigin(cx, cy)
        root.playTransition(cx, cy, nextMode)
        root.bridge.theme.setMode(nextMode)
        root.requestThemeToggle(Qt.point(cx, cy), nextMode)
    }

    function playTransition(cx, cy, mode) {
        if (root.lowMemoryVisuals)
            return
        themeTransitionReleaseTimer.stop()
        pendingTransitionX = cx
        pendingTransitionY = cy
        pendingTransitionMode = mode
        if (transitionLayerLoader.item) {
            transitionLayerLoader.item.play(pendingTransitionX, pendingTransitionY, pendingTransitionMode)
        } else {
            transitionLayerLoader.active = true
        }
    }

    function prepareThemeTransition() {
        if (root.lowMemoryVisuals || transitionLayerLoader.active)
            return
        transitionLayerPreloaded = true
        transitionLayerLoader.active = true
        themeTransitionReleaseTimer.restart()
    }

    function adjustFontScaleByWheel(deltaY) {
        if (!root.bridge || !root.bridge.theme)
            return
        if (deltaY > 0)
            root.bridge.theme.increaseFontScale()
        else if (deltaY < 0)
            root.bridge.theme.decreaseFontScale()
    }

    function smokeOpenTitleMenu() {
        return titleBarControl.smokeOpenFirstMenu()
    }

    function smokeOpenPalette() {
        return titleBarControl.smokeOpenPalette()
    }

    function smokePopupState() {
        return titleBarControl.smokePopupState()
    }

    function smokeShowPage(pageKey) {
        if (contentHost.children.length <= 0 || !contentHost.children[0].smokeShowPage)
            return false
        return contentHost.children[0].smokeShowPage(pageKey)
    }

    function requestMainClose() {
        if (root.windowKey !== "main")
            return false
        if (typeof App !== "undefined" && App && App.logRuntime)
            App.logRuntime("AppWindow.requestMainClose entered")
        if (root.bridge && root.bridge.window && root.bridge.window.saveNativeManagedWindowState)
            root.bridge.window.saveNativeManagedWindowState(root)
        if (typeof App !== "undefined" && App && App.tray && App.tray.handleClosing(root)) {
            if (App.logRuntime)
                App.logRuntime("AppWindow.requestMainClose handled by tray")
            return true
        }
        if (typeof App !== "undefined" && App && App.logRuntime)
            App.logRuntime("AppWindow.requestMainClose falling back to exit")
        if (typeof App !== "undefined" && App && App.exitApplication)
            App.exitApplication()
        else
            root.close()
        return true
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

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        visible: root.linuxCsdShadow
        z: -1
    }

    LinuxCsdShadowLayer {
        id: linuxCsdShadowLayer
        anchors.fill: frameRoot
        shadowInset: linuxCsdController.snappedShadowInset
        shadowOpacity: root.externalShadowOpacity
        cornerRadius: root.cornerRadius
        shadowSource: Qt.resolvedUrl("../../resources/images/window_shadow.png")
        shadowVisible: root.csdShadowVisible
    }

    // Linux CSD: the outer Window carries transparent shadow only.
    // Internal popups, hit-tests, saved geometry, and snap logic must use frameRoot/content bounds.
    Item {
        id: frameRoot
        objectName: "appFrameRoot"
        property int visualRadius: root.cornerRadius
        property int shadowVisualInset: 0
        property int cornerRadius: root.cornerRadius
        anchors.fill: parent
        anchors.leftMargin: linuxCsdController.snappedShadowInset
        anchors.topMargin: linuxCsdController.snappedShadowInset
        anchors.rightMargin: linuxCsdController.snappedShadowInset
        anchors.bottomMargin: linuxCsdController.snappedShadowInset
        clip: true
        z: 1

        Rectangle {
            id: background
            anchors.fill: parent
            radius: frameRoot.visualRadius
            antialiasing: true
            color: Core.Theme.color.surface
            border.color: "transparent"
            border.width: 0
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on radius {
                enabled: !root.windowMaximized && !root.snappedVisual
                NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
            }
        }

        Loader {
            id: transitionLayerLoader
            anchors.fill: parent
            z: 1
            active: root.transitionLayerPreloaded
            sourceComponent: ThemeTransitionLayer {
                radius: frameRoot.visualRadius
                renderScale: Core.Theme.lowMemoryMode ? 0.15 : 0.35
                onFinished: {
                    root.transitionLayerPreloaded = false
                    transitionLayerLoader.active = false
                    if (root.windowKey === "main" && root.bridge && root.bridge.endVisualTransitionSoon)
                        root.bridge.endVisualTransitionSoon()
                }
            }
            onLoaded: {
                if (item && root.pendingTransitionMode.length > 0)
                    item.play(root.pendingTransitionX, root.pendingTransitionY, root.pendingTransitionMode)
            }
        }

        Timer {
            id: themeTransitionReleaseTimer
            interval: 1800
            repeat: false
            onTriggered: {
                if (transitionLayerLoader.active && transitionLayerLoader.item && !transitionLayerLoader.item.running) {
                    root.transitionLayerPreloaded = false
                    transitionLayerLoader.active = false
                }
            }
        }

        Item {
            id: mainColumn
            anchors.fill: parent
            z: 2

            TitleBar {
                id: titleBarControl
                y: 0
                z: 2
                width: parent.width
                height: Core.Theme.metrics.titleBarHeight
                windowTitle: root.title.length > 0 ? root.title : Core.AppInfo.windowTitle
                frameRadius: root.cornerRadius
                alwaysOnTop: root.alwaysOnTop
                showNavToggle: root.showNavToggle
                showColorButton: root.showColorButton
                showThemeButton: root.showThemeButton
                showPinButton: root.showPinButton
                showResourceStats: typeof App !== "undefined" && App && App.titleBarResourceStatsEnabled
                resourceStats: (typeof App !== "undefined" && App && App.titleBarResourceStats) ? App.titleBarResourceStats : ({})
                windowMaximized: root.windowMaximized
                useNativeCaption: !linuxCsdController.interactiveCaptionMode
                systemMoveOnPress: linuxCsdController.interactiveCaptionMode
                popupHost: linuxCsdController.interactiveCaptionMode ? frameRoot : null

                onActivateRequested: {
                    root.raiseSelf()
                    const shadow = root.qmlShadowWindow()
                    if (shadow)
                        shadow.forceStackSync(1)
                    else if (root.nativeShadowDisplayReady)
                        externalShadow.syncNativeShadow(root)
                }

                onMoveRequested: function(localX, localY) {
                    root.raiseSelf()
                    titleBarControl._systemMoveAccepted = false
                    if (linuxCsdController.tryStartTitleBarMove(root.snappedVisual)) {
                        titleBarControl._systemMoveAccepted = true
                        titleBarControl.clearPointerTracking()
                        return
                    }
                    linuxCsdController.beginFallbackMove(localX, localY)
                }
                onMoveUpdated: {
                    linuxCsdController.updateFallbackMove()
                }
                onMoveFinished: {
                    linuxCsdController.endFallbackMove()
                }

                onToggleMaximizeRequested: root.toggleMaximized()
                onMinimizeRequested: root.showMinimized()
                onCloseRequested: {
                    if (root.windowKey === "main")
                        root.requestMainClose()
                    else if (root.windowKey.indexOf("child-") === 0)
                        root.finalizeChildClose()
                    else
                        root.close()
                }
                onThemeToggleRequested: function(localPos, nextMode) {
                    root.changeThemeWithRipple(nextMode, localPos.x, localPos.y)
                }
                onThemeTogglePrepared: root.prepareThemeTransition()
                onAlwaysOnTopRequested: function(enabled) {
                    root.alwaysOnTop = enabled
                    if (root.bridge && root.bridge.window)
                        root.bridge.window.setAlwaysOnTop(root, enabled)
                    root.requestAlwaysOnTop(enabled)
                }
                onToggleNavRequested: root.navToggleRequested()
            }

            Connections {
                target: titleBarControl
                function onPaletteButtonItemChanged() { root.registerNativeClickableItem(titleBarControl.paletteButtonItem) }
                function onThemeButtonItemChanged() { root.registerNativeClickableItem(titleBarControl.themeButtonItem) }
                function onPinButtonItemChanged() { root.registerNativeClickableItem(titleBarControl.pinButtonItem) }
            }

            Item {
                id: contentHost
                y: titleBarControl.height
                z: 1
                width: parent.width
                height: Math.max(0, parent.height - titleBarControl.height)
                clip: true
            }
        }

        Rectangle {
            id: windowEdgeOverlay
            anchors.fill: parent
            anchors.margins: root.stableHairline
            z: 90
            radius: Math.max(0, frameRoot.visualRadius - root.stableHairline)
            color: "transparent"
            visible: frameRoot.visualRadius > 0
            border.color: frameRoot.visualRadius > 0 ? Core.Theme.color.windowEdge : "transparent"
            border.width: frameRoot.visualRadius > 0 ? root.stableHairline : 0
            antialiasing: true
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

        ResizeArea {
            id: resizeArea
            anchors.fill: parent
            enabled: linuxCsdController.resizeAreaEnabled(root.visibility, root.snappedVisual)
            windowObject: root
            bridge: root.bridge
            grip: Core.Theme.metrics.resizeEdgeInset
            cornerGrip: Core.Theme.metrics.resizeCornerInset
            z: 100
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
    Timer {
        id: resizeTrimTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (root.windowKey === "main" && root.bridge && root.bridge.trimResizeMemory)
                root.bridge.trimResizeMemory()
            else if (root.windowKey === "main" && root.bridge && root.bridge.trimMemory)
                root.bridge.trimMemory()
        }
    }

    Connections {
        target: root.bridge ? root.bridge.theme : null
        function onModeChanged(mode) {
            root.syncNativeWindowState()
            linuxCsdController.syncNativeShellBackground()
            nativeAgent.setCornerRadius(root.cornerRadius)
            nativeAgent.setShadowAsset(Qt.resolvedUrl("../../resources/images/window_shadow.png"), root.externalShadowMargin,
                                       root.externalShadowOpacity)
            root.syncExternalShadow()
            if (root._localThemeAnimation) {
                root._localThemeAnimation = false
                return
            }
            root.playTransition(frameRoot.width / 2, frameRoot.height / 2, mode)
        }
    }

    Connections {
        target: (typeof App !== "undefined" && App && App.tray) ? App.tray : null
        function onMinimizeToTrayChanged(_enabled) {
            root.syncNativeFastExitPolicy()
        }
    }

    Component.onDestruction: root.cleanupExternalShadow()

    onXChanged: { snapStateSyncTimer.restart(); stableNativeShadowSyncTimer.restart() }
    onYChanged: { snapStateSyncTimer.restart(); stableNativeShadowSyncTimer.restart() }
    onWidthChanged: {
        snapStateSyncTimer.restart()
        stableNativeShadowSyncTimer.restart()
        if (root.windowKey === "main")
            resizeTrimTimer.restart()
        windowEvent("widthChanged", ({ "width": width }))
    }
    onHeightChanged: {
        snapStateSyncTimer.restart()
        stableNativeShadowSyncTimer.restart()
        if (root.windowKey === "main")
            resizeTrimTimer.restart()
        windowEvent("heightChanged", ({ "height": height }))
    }
    onVisibilityChanged: {
        linuxCsdController.handleVisibilityChanged(nativeAgent.nativeSystemMoveFromMaximized)
        snapStateSyncTimer.restart()
        windowEvent("visibilityChanged", ({ "visibility": root.visibility }))
        root.scheduleNativeShadowShow()
    }
    onVisibleChanged: {
        if (root._destroyingChildWindow)
            return
        if (!root.visible)
            root.nativeShadowDisplayReady = false
        root.scheduleNativeShadowShow()
    }
    onFrameSwapped: {
        root.firstFrameReady = true
        linuxCsdController.finishDprTransition()
        root.markNativeShadowDisplayReady()
    }
    onCornerRadiusChanged: {
        nativeAgent.setCornerRadius(root.cornerRadius)
        linuxCsdController.handleCornerRadiusChanged()
        root.syncExternalShadow()
    }
    onCustomExternalShadowChanged: {
        nativeAgent.setCustomShadowEnabled(root.customExternalShadow)
        root.syncExternalShadow()
    }
    onCustomShadowEnabledChanged: root.syncExternalShadow()
    onShowColorButtonChanged: {
        if (!root.showColorButton)
            root.unregisterNativeClickableItem(titleBarControl.paletteButtonItem)
    }
    onShowThemeButtonChanged: {
        if (!root.showThemeButton)
            root.unregisterNativeClickableItem(titleBarControl.themeButtonItem)
    }
    onShowPinButtonChanged: {
        if (!root.showPinButton)
            root.unregisterNativeClickableItem(titleBarControl.pinButtonItem)
    }
    onAlwaysOnTopChanged: {
        if (root.nativeExternalShadow) {
            root.syncExternalShadow()
            if (root.customShadowEnabled)
                externalShadow.syncNativeShadow(root)
        } else if (root.qmlExternalShadow) {
            const shadow = root.qmlShadowWindow()
            if (shadow)
                shadow.forceStackSync(3)
        }
    }
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
        if (active && root.nativeExternalShadow && root.nativeShadowDisplayReady) {
            root.syncExternalShadow()
            if (root.customShadowEnabled)
                externalShadow.syncNativeShadow(root)
        }
    }
    onClosing: function(close) {
        if (root.windowKey === "main") {
            close.accepted = false
            root.requestMainClose()
            return
        }
        if (root.windowKey.indexOf("child-") === 0 && typeof App !== "undefined" && App && App.dialogs && App.dialogs.closeChildWindow) {
            close.accepted = true
            root.finalizeChildClose()
            return
        }
        close.accepted = true
    }
}
