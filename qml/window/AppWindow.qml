import QtQuick
import QtQuick.Window
import QtQuick.Controls
import FramelessNative 1.0
import "../core" as Core
import "../controls"

Window {
    id: root

    readonly property real devicePixelRatio: Math.max(1.0, (root.screen ? root.screen.devicePixelRatio : Screen.devicePixelRatio))
    readonly property real physicalPixel: 1.0 / devicePixelRatio
    readonly property real stableHairline: Math.max(1.0, physicalPixel)

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
                                  && !root.linuxCsdShadowDisabled()
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
    property bool csdShadowVisible: root.linuxCsdShadow
                                    && root.customShadowEnabled
                                    && root.cornerRadius > 0
                                    && !root._linuxCsdWindowStateTransition
    property int linuxCsdShadowInset: (root.linuxCsdShadow && !root.windowMaximized && !root.snappedVisual)
                                     ? root.externalShadowMargin
                                     : 0
    property int shadowVisualInset: root.linuxCsdShadowInset
    property int windowStateGeometryInset: 0
    property bool _applyingCsdInsetGeometry: false
    property int _appliedCsdShadowInset: 0
    property bool _pendingLinuxCsdStateSync: false
    property bool _linuxCsdWindowStateTransition: false
    property int normalCornerRadius: Core.Theme.radius.window
    property int cornerRadius: (root.windowMaximized || root.snappedVisual || effectiveCornerPolicy === "square") ? 0 : normalCornerRadius
    property bool _localThemeAnimation: false
    property bool _childCloseScheduled: false
    property string pendingTransitionMode: ""
    property real pendingTransitionX: 0
    property real pendingTransitionY: 0
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
    color: root.shellBackgroundColorForState()
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
        onNativeSystemMoveFinished: titleBarControl.resetDragState()
    }

    ExternalShadowController {
        id: externalShadow
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

    function shellBackgroundColorForState() {
        if (root.linuxCsdShadow && root._linuxCsdWindowStateTransition)
            return Core.Theme.color.surface
        if (root.linuxCsdShadow)
            return root.linuxCsdShadowInset > 0 ? "transparent" : Core.Theme.color.surface
        return Qt.platform.os === "windows" ? Core.Theme.color.surface : "transparent"
    }

    function syncNativeShellBackground() {
        if (nativeAgent && nativeAgent.setShellBackgroundColor)
            nativeAgent.setShellBackgroundColor(root.shellBackgroundColorForState())
    }

    function registerNativeChrome() {
        if (nativeAgent.setClientSideShadowMode)
            nativeAgent.setClientSideShadowMode(root.linuxCsdShadow)
        nativeAgent.setup(root)
        root.syncNativeShellBackground()
        root.syncNativeFastExitPolicy()
        root.nativeChromeRegistered = true
        nativeAgent.setCustomShadowEnabled(root.customExternalShadow)
        nativeAgent.setCornerRadius(root.cornerRadius)
        nativeAgent.setShadowAsset(Qt.resolvedUrl("../../resources/images/window_shadow.png"), root.externalShadowMargin,
                                   root.externalShadowOpacity)
        nativeAgent.setResizeHitTestInsets(Core.Theme.metrics.resizeEdgeInset,
                                           Core.Theme.metrics.resizeCornerInset)
        root.syncGtkFrameExtents()

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

    function linuxCsdShadowDisabled() {
        if (typeof App === "undefined" || !App || !App.envValue)
            return false
        const value = String(App.envValue("QROUNDEDFRAME_DISABLE_LINUX_CSD_SHADOW") || "").toLowerCase()
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
        root.applyLinuxCsdShadowInset()
        root.syncExternalShadow()
    }

    function scheduleLinuxCsdStateSync() {
        if (!root.linuxCsdShadow) {
            root.syncNativeWindowState()
            return
        }
        if (root._pendingLinuxCsdStateSync)
            return
        root._pendingLinuxCsdStateSync = true
        Qt.callLater(function() {
            root._pendingLinuxCsdStateSync = false
            root.syncNativeWindowState()
            nativeAgent.setCornerRadius(root.cornerRadius)
            root.syncGtkFrameExtents()
        })
    }

    function applyLinuxCsdShadowInset() {
        if (!root.linuxCsdShadow)
            return
        const nextInset = root.linuxCsdShadowInset
        const previousInset = root._appliedCsdShadowInset
        if (nextInset === previousInset || root._applyingCsdInsetGeometry)
            return
        root._applyingCsdInsetGeometry = true
        root._appliedCsdShadowInset = nextInset
        root._applyingCsdInsetGeometry = false
        root.syncGtkFrameExtents()
    }

    function syncGtkFrameExtents() {
        if (!nativeAgent || !nativeAgent.setGtkFrameExtents)
            return
        const inset = root.linuxCsdShadow && !root._linuxCsdWindowStateTransition ? root.linuxCsdShadowInset : 0
        nativeAgent.setGtkFrameExtents(inset, inset, inset, inset)
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
            return
        }
        root._linuxCsdWindowStateTransition = root.linuxCsdShadow
        root.syncGtkFrameExtents()
        root.syncNativeShellBackground()
        if (wasMaximized) {
            root.showNormal()
        } else {
            root.showMaximized()
        }
        Qt.callLater(function() {
            root.syncNativeWindowState()
            nativeAgent.setCornerRadius(root.cornerRadius)
            root._linuxCsdWindowStateTransition = false
            root.syncGtkFrameExtents()
            root.syncNativeShellBackground()
        })
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
        root.playTransition(cx, cy, nextMode)
        root.bridge.theme.setMode(nextMode)
        root.requestThemeToggle(Qt.point(cx, cy), nextMode)
    }

    function playTransition(cx, cy, mode) {
        if (root.lowMemoryVisuals)
            return
        pendingTransitionX = cx
        pendingTransitionY = cy
        pendingTransitionMode = mode
        if (transitionLayerLoader.item) {
            transitionLayerLoader.item.play(pendingTransitionX, pendingTransitionY, pendingTransitionMode)
        } else {
            transitionLayerLoader.active = true
        }
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
        root._closingMainWindow = true
        stableNativeShadowSyncTimer.stop()
        snapStateSyncTimer.stop()
        resizeTrimTimer.stop()
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

    Item {
        id: linuxCsdShadowLayer
        anchors.fill: frameRoot
        anchors.margins: -root.linuxCsdShadowInset
        visible: root.csdShadowVisible
        opacity: root.externalShadowOpacity
        z: 0

        readonly property url shadowSource: Qt.resolvedUrl("../../resources/images/window_shadow.png")
        readonly property int m: root.linuxCsdShadowInset
        readonly property int sourceSize: 160
        readonly property int innerRadiusBias: Qt.platform.os === "linux" ? 2 : 0
        readonly property int c: Math.min(sourceSize / 2, m + root.cornerRadius + innerRadiusBias)
        readonly property int centerSize: Math.max(1, sourceSize - c * 2)

        Image {
            x: 0; y: 0; width: linuxCsdShadowLayer.c; height: linuxCsdShadowLayer.c
            source: linuxCsdShadowLayer.shadowSource
            sourceClipRect: Qt.rect(0, 0, linuxCsdShadowLayer.c, linuxCsdShadowLayer.c)
            fillMode: Image.Stretch
            smooth: false
            cache: true
        }
        Image {
            x: linuxCsdShadowLayer.c; y: 0
            width: Math.max(0, linuxCsdShadowLayer.width - linuxCsdShadowLayer.c * 2)
            height: linuxCsdShadowLayer.m
            source: linuxCsdShadowLayer.shadowSource
            sourceClipRect: Qt.rect(linuxCsdShadowLayer.c, 0, linuxCsdShadowLayer.centerSize, linuxCsdShadowLayer.m)
            fillMode: Image.Stretch
            smooth: false
            cache: true
        }
        Image {
            x: linuxCsdShadowLayer.width - linuxCsdShadowLayer.c; y: 0
            width: linuxCsdShadowLayer.c; height: linuxCsdShadowLayer.c
            source: linuxCsdShadowLayer.shadowSource
            sourceClipRect: Qt.rect(linuxCsdShadowLayer.sourceSize - linuxCsdShadowLayer.c, 0, linuxCsdShadowLayer.c, linuxCsdShadowLayer.c)
            fillMode: Image.Stretch
            smooth: false
            cache: true
        }
        Image {
            x: 0; y: linuxCsdShadowLayer.c
            width: linuxCsdShadowLayer.m
            height: Math.max(0, linuxCsdShadowLayer.height - linuxCsdShadowLayer.c * 2)
            source: linuxCsdShadowLayer.shadowSource
            sourceClipRect: Qt.rect(0, linuxCsdShadowLayer.c, linuxCsdShadowLayer.m, linuxCsdShadowLayer.centerSize)
            fillMode: Image.Stretch
            smooth: false
            cache: true
        }
        Image {
            x: linuxCsdShadowLayer.width - linuxCsdShadowLayer.m; y: linuxCsdShadowLayer.c
            width: linuxCsdShadowLayer.m
            height: Math.max(0, linuxCsdShadowLayer.height - linuxCsdShadowLayer.c * 2)
            source: linuxCsdShadowLayer.shadowSource
            sourceClipRect: Qt.rect(linuxCsdShadowLayer.sourceSize - linuxCsdShadowLayer.m, linuxCsdShadowLayer.c, linuxCsdShadowLayer.m, linuxCsdShadowLayer.centerSize)
            fillMode: Image.Stretch
            smooth: false
            cache: true
        }
        Image {
            x: 0; y: linuxCsdShadowLayer.height - linuxCsdShadowLayer.c
            width: linuxCsdShadowLayer.c; height: linuxCsdShadowLayer.c
            source: linuxCsdShadowLayer.shadowSource
            sourceClipRect: Qt.rect(0, linuxCsdShadowLayer.sourceSize - linuxCsdShadowLayer.c, linuxCsdShadowLayer.c, linuxCsdShadowLayer.c)
            fillMode: Image.Stretch
            smooth: false
            cache: true
        }
        Image {
            x: linuxCsdShadowLayer.c; y: linuxCsdShadowLayer.height - linuxCsdShadowLayer.m
            width: Math.max(0, linuxCsdShadowLayer.width - linuxCsdShadowLayer.c * 2)
            height: linuxCsdShadowLayer.m
            source: linuxCsdShadowLayer.shadowSource
            sourceClipRect: Qt.rect(linuxCsdShadowLayer.c, linuxCsdShadowLayer.sourceSize - linuxCsdShadowLayer.m, linuxCsdShadowLayer.centerSize, linuxCsdShadowLayer.m)
            fillMode: Image.Stretch
            smooth: false
            cache: true
        }
        Image {
            x: linuxCsdShadowLayer.width - linuxCsdShadowLayer.c
            y: linuxCsdShadowLayer.height - linuxCsdShadowLayer.c
            width: linuxCsdShadowLayer.c; height: linuxCsdShadowLayer.c
            source: linuxCsdShadowLayer.shadowSource
            sourceClipRect: Qt.rect(linuxCsdShadowLayer.sourceSize - linuxCsdShadowLayer.c, linuxCsdShadowLayer.sourceSize - linuxCsdShadowLayer.c, linuxCsdShadowLayer.c, linuxCsdShadowLayer.c)
            fillMode: Image.Stretch
            smooth: false
            cache: true
        }
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
        anchors.leftMargin: root.linuxCsdShadowInset
        anchors.topMargin: root.linuxCsdShadowInset
        anchors.rightMargin: root.linuxCsdShadowInset
        anchors.bottomMargin: root.linuxCsdShadowInset
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
            active: false
            sourceComponent: ThemeTransitionLayer {
                radius: frameRoot.visualRadius
                renderScale: Core.Theme.lowMemoryMode ? 0.15 : 0.35
                onFinished: {
                    transitionLayerLoader.active = false
                    if (root.windowKey === "main" && root.bridge && root.bridge.trimMemoryNow)
                        Qt.callLater(root.bridge.trimMemoryNow)
                }
            }
            onLoaded: {
                if (item && root.pendingTransitionMode.length > 0)
                    item.play(root.pendingTransitionX, root.pendingTransitionY, root.pendingTransitionMode)
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
                windowMaximized: root.windowMaximized
                useNativeCaption: !root.linuxCsdShadow
                systemMoveOnPress: root.linuxCsdShadow
                popupHost: frameRoot

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
                    if (root.linuxCsdShadow && nativeAgent.startSystemMove && nativeAgent.startSystemMove(root)) {
                        titleBarControl._systemMoveAccepted = true
                        titleBarControl.clearPointerTracking()
                        return
                    }
                    if (root.linuxCsdShadow && root.bridge && root.bridge.window)
                        root.bridge.window.beginMove(root, localX, localY)
                }
                onMoveUpdated: {
                    if (root.linuxCsdShadow && root.bridge && root.bridge.window)
                        root.bridge.window.updateMove(root)
                }
                onMoveFinished: {
                    if (root.linuxCsdShadow && root.bridge && root.bridge.window)
                        root.bridge.window.endMove(root)
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
            enabled: root.linuxCsdShadow
                     && root.visibility !== Window.Maximized
                     && root.visibility !== Window.FullScreen
                     && !root.snappedVisual
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
            root.syncNativeShellBackground()
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
        if (root._closingMainWindow)
            return
        root.scheduleLinuxCsdStateSync()
        snapStateSyncTimer.restart()
        windowEvent("visibilityChanged", ({ "visibility": root.visibility }))
        root.scheduleNativeShadowShow()
    }
    onVisibleChanged: {
        if (root._destroyingChildWindow || root._closingMainWindow)
            return
        if (!root.visible)
            root.nativeShadowDisplayReady = false
        root.scheduleNativeShadowShow()
    }
    onFrameSwapped: {
        root.firstFrameReady = true
        root.markNativeShadowDisplayReady()
    }
    onCornerRadiusChanged: {
        nativeAgent.setCornerRadius(root.cornerRadius)
        root.syncGtkFrameExtents()
        root.syncExternalShadow()
    }
    onCustomExternalShadowChanged: {
        nativeAgent.setCustomShadowEnabled(root.customExternalShadow)
        root.syncExternalShadow()
    }
    onCustomShadowEnabledChanged: root.syncExternalShadow()
    onLinuxCsdShadowInsetChanged: {
        root.syncGtkFrameExtents()
        root.syncNativeShellBackground()
    }
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







