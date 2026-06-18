import QtQuick
import QtQuick.Window
import QtQuick.Controls
import "../core" as Core
import "../controls"

Window {
    id: root

    readonly property real devicePixelRatio: Math.max(1.0, (root.screen ? root.screen.devicePixelRatio : Screen.devicePixelRatio))
    readonly property real physicalPixel: 1.0 / devicePixelRatio
    readonly property real stableHairline: Math.max(1.0, physicalPixel)

    property var bridge
    property bool customChromeEnabled: root.bridge && root.bridge.window
                                       && root.bridge.window.customChromeEnabled !== undefined
                                       ? root.bridge.window.customChromeEnabled
                                       : true
    property bool useCustomShadow: root.bridge && root.bridge.window
                                   && root.bridge.window.customShadowEnabled !== undefined
                                   ? root.bridge.window.customShadowEnabled
                                   : root.customChromeEnabled

    flags: Qt.Window
           | (root.customChromeEnabled ? Qt.FramelessWindowHint : 0)
           | (root.useCustomShadow ? Qt.NoDropShadowWindowHint : 0)
    color: "transparent"
    visible: true

    default property alias content: contentHost.data

    property string windowKey: "window"
    property bool autoRestoreWindowState: true
    property alias titleBar: titleBarControl
    property bool alwaysOnTop: false
    property bool shadowEnabled: true
    property bool showNavToggle: true
    property bool showColorButton: Core.Theme.showColorButton
    property bool showThemeButton: true
    property bool showPinButton: true
    property bool lowMemoryVisuals: root.windowKey !== "main"
    property int normalCornerRadius: Core.Theme.radius.window
    property int cornerRadius: (visibility === Window.Maximized || visibility === Window.FullScreen) ? 0 : normalCornerRadius
    property bool resizeEnabled: root.customChromeEnabled && visibility !== Window.Maximized && visibility !== Window.FullScreen
    property bool _localThemeAnimation: false
    property bool _snappedVisualSyncPending: false
    property bool nativeInteractionActive: false
    property bool nativeCaptionMovePending: false
    property bool nativeDragRestoreVisual: false
    property string pendingTransitionMode: ""
    property real pendingTransitionX: 0
    property real pendingTransitionY: 0
    property bool snappedVisual: false
    property string snappedVisualKind: ""
    property bool snapShadowSuppressed: false
    property bool inlineShadowEnabled: Qt.platform.os === "windows" && root.useCustomShadow
    property bool inlineShadowVisible: shadowEnabled
                                       && root.inlineShadowEnabled
                                       && !root.snapShadowSuppressed
                                       && cornerRadius > 0
                                       && visibility !== Window.Minimized
                                       && visibility !== Window.Maximized
                                       && visibility !== Window.FullScreen
                                       && !root.nativeDragRestoreVisual
                                       && !snappedVisual
    property int normalShadowVisualInset: Core.Theme.dp(32)
    property int shadowVisualInset: inlineShadowVisible ? normalShadowVisualInset : 0
    property real inlineShadowTargetOpacity: Core.Theme.mode === "dark" ? 1.0 : 0.78
    property real inlineShadowOpacity: inlineShadowVisible ? inlineShadowTargetOpacity : 0
    property bool normalVisualMarginsActive: inlineShadowVisible || (root.useCustomShadow && nativeDragRestoreVisual)
    property int frameMarginLeft: normalVisualMarginsActive ? normalShadowVisualInset : 0
    property int frameMarginTop: normalVisualMarginsActive ? normalShadowVisualInset : 0
    property int frameMarginRight: normalVisualMarginsActive ? normalShadowVisualInset : 0
    property int frameMarginBottom: normalVisualMarginsActive ? normalShadowVisualInset : 0
    property int nativeShadowInsetLeft: frameMarginLeft
    property int nativeShadowInsetTop: frameMarginTop
    property int nativeShadowInsetRight: frameMarginRight
    property int nativeShadowInsetBottom: frameMarginBottom
    property int nativeShadowInset: Math.max(nativeShadowInsetLeft, nativeShadowInsetTop, nativeShadowInsetRight, nativeShadowInsetBottom)
    property bool customShadowVisible: shadowEnabled
                                       && root.useCustomShadow
                                       && !root.inlineShadowEnabled
                                       && !root.snapShadowSuppressed
                                       && cornerRadius > 0
                                       && visibility !== Window.Minimized
                                       && visibility !== Window.Maximized
                                       && visibility !== Window.FullScreen
                                       && !snappedVisual
    property int nativeTitleBarHeight: Math.round(titleBarControl.nativeTitleBarHeight)
    property int nativeCaptionLeftA: Math.round(titleBarControl.nativeCaptionLeftA)
    property int nativeCaptionRightA: Math.round(titleBarControl.nativeCaptionRightA)
    property int nativeCaptionLeftB: Math.round(titleBarControl.nativeCaptionLeftB)
    property int nativeCaptionRightB: Math.round(titleBarControl.nativeCaptionRightB)

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
        if (transitionLayer.item) {
            transitionLayer.item.play(pendingTransitionX, pendingTransitionY, pendingTransitionMode)
        } else {
            transitionLayer.active = true
        }
    }

    function prepareThemeTransition() {
        if (root.lowMemoryVisuals || transitionLayer.active)
            return
        transitionLayer.active = true
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

    function restorePersistedWindowState() {
        if (root.bridge && root.bridge.window)
            root.bridge.window.restoreWindowState(root)
    }

    function applySnappedVisualFromGeometry(force) {
        if (root.nativeInteractionActive && !force)
            return
        if (!root.bridge || !root.bridge.window)
            return
        const kind = root.bridge.window.snapState ? root.bridge.window.snapState(root) : (root.bridge.window.isSnappedState(root) ? "snapped" : "")
        const snapped = kind !== ""
        if (root.snappedVisual !== snapped)
            root.snappedVisual = snapped
        if (root.snappedVisualKind !== kind)
            root.snappedVisualKind = kind
        if (snapped)
            root.snapShadowSuppressed = false
    }

    function syncSnappedVisualFromGeometry() {
        root._snappedVisualSyncPending = false
        root.applySnappedVisualFromGeometry(false)
    }

    function requestSnappedVisualSync(force) {
        if (!root.bridge || !root.bridge.window)
            return
        root.applySnappedVisualFromGeometry(force === true)
        root.scheduleSnappedVisualSync()
    }

    function scheduleSnappedVisualSync() {
        if (!root.bridge || !root.bridge.window)
            return
        if (root._snappedVisualSyncPending)
            return
        root._snappedVisualSyncPending = true
        Qt.callLater(root.syncSnappedVisualFromGeometry)
    }

    function syncInlineShadowOpacity(animate) {
        inlineShadowFade.stop()
        const targetOpacity = root.inlineShadowVisible ? root.inlineShadowTargetOpacity : 0
        if (root.inlineShadowVisible && animate) {
            root.inlineShadowOpacity = 0
            inlineShadowFade.to = targetOpacity
            inlineShadowFade.start()
        } else {
            root.inlineShadowOpacity = targetOpacity
        }
    }

    onInlineShadowVisibleChanged: syncInlineShadowOpacity(root.inlineShadowVisible)
    onInlineShadowTargetOpacityChanged: {
        if (root.inlineShadowVisible && !inlineShadowFade.running)
            root.inlineShadowOpacity = root.inlineShadowTargetOpacity
    }

    WheelHandler {
        acceptedModifiers: Qt.ControlModifier
        target: null
        onWheel: function(event) {
            root.adjustFontScaleByWheel(event.angleDelta.y)
            event.accepted = true
        }
    }

    ShadowWindow {
        id: customShadow
        targetWindow: root.customShadowVisible ? root : null
        stackController: root.customShadowVisible && root.bridge && root.bridge.window ? root.bridge.window : null
        shadowEnabled: root.customShadowVisible
        cornerRadius: root.cornerRadius
    }

    BorderImage {
        id: inlineShadow
        anchors.fill: parent
        visible: root.inlineShadowVisible || opacity > 0.001
        source: "../../resources/images/window_shadow.png"
        border.left: root.shadowVisualInset
        border.top: root.shadowVisualInset
        border.right: root.shadowVisualInset
        border.bottom: root.shadowVisualInset
        horizontalTileMode: BorderImage.Stretch
        verticalTileMode: BorderImage.Stretch
        smooth: false
        cache: true
        opacity: root.inlineShadowOpacity
        z: 0
    }

    NumberAnimation {
        id: inlineShadowFade
        target: root
        property: "inlineShadowOpacity"
        duration: 2000
        easing.type: Easing.OutCubic
    }

    Item {
        id: frameRoot
        anchors.fill: parent
        anchors.leftMargin: root.frameMarginLeft
        anchors.topMargin: root.frameMarginTop
        anchors.rightMargin: root.frameMarginRight
        anchors.bottomMargin: root.frameMarginBottom
        clip: false
        z: 1

        Rectangle {
            id: background
            antialiasing: true
            anchors.fill: parent
            radius: root.cornerRadius
            color: Core.Theme.color.surface
            border.color: Core.Theme.color.outline
            border.width: (root.cornerRadius === 0 || root.snappedVisual) ? 0 : root.stableHairline
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on radius { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }
        }

        Loader {
            id: transitionLayer
            anchors.fill: parent
            active: false
            z: 1
            sourceComponent: ThemeTransitionLayer {
                radius: root.cornerRadius
                renderScale: Core.Theme.lowMemoryMode ? 0.15 : 0.35
                onFinished: {
                    transitionLayer.active = false
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
                if (transitionLayer.active && transitionLayer.item && !transitionLayer.item.running)
                    transitionLayer.active = false
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
                windowTitle: root.title
                frameRadius: root.cornerRadius
                alwaysOnTop: root.alwaysOnTop
                showNavToggle: root.showNavToggle
                showColorButton: root.showColorButton
                showThemeButton: root.showThemeButton
                showPinButton: root.showPinButton
                showWindowControls: root.customChromeEnabled
                windowMaximized: root.bridge && root.bridge.window ? root.bridge.window.isMaximizedState(root) : root.visibility === Window.Maximized
                useNativeCaption: root.customChromeEnabled && Qt.platform.os === "windows" && root.bridge && root.bridge.window && root.bridge.window.nativeResize

                onActivateRequested: {
                    root.raiseSelf()
                    if (root.bridge && root.bridge.window)
                        root.bridge.window.activateWindow(root)
                    customShadow.forceStackSync(1)
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
                onThemeTogglePrepared: root.prepareThemeTransition()

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
            radius: Math.max(0, root.cornerRadius - root.stableHairline)
            color: "transparent"
            visible: root.cornerRadius > 0
            border.color: root.cornerRadius > 0 ? Core.Theme.color.windowEdge : "transparent"
            border.width: root.cornerRadius > 0 ? root.stableHairline : 0
            antialiasing: true
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
            grip: Core.Theme.metrics.resizeEdgeInset
            cornerGrip: Core.Theme.metrics.resizeCornerInset
            z: 100
        }
    }

    SnapPreviewWindow {
        id: snapPreview
        transientParent: root
    }

    Timer {
        id: chromeRefreshTimer
        interval: 36
        repeat: false
        onTriggered: if (bridge) bridge.window.refreshNativeFrame(root)
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
        target: root.bridge ? root.bridge.window : null
        function onCaptionPressed(key) {
            if (key === root.windowKey) {
                root.nativeCaptionMovePending = root.snappedVisual
                                                || root.visibility === Window.Maximized
                                                || root.visibility === Window.FullScreen
                titleBarControl.closeMenus()
                customShadow.forceStackSync(1)
            }
        }
        function onNativeMoveStarted(key) {
            if (key === root.windowKey) {
                root.nativeInteractionActive = true
                if (root.nativeCaptionMovePending)
                    root.nativeDragRestoreVisual = root.useCustomShadow
                customShadow.forceStackSync(1)
            }
        }
        function onNativeMoveFinished(key) {
            if (key === root.windowKey) {
                root.nativeInteractionActive = false
                root.nativeCaptionMovePending = false
                root.nativeDragRestoreVisual = false
                if (!(root.bridge && root.bridge.window && root.bridge.window.isSnappedState(root)))
                    root.snapShadowSuppressed = false
                root.requestSnappedVisualSync(true)
                customShadow.forceStackSync(2)
            }
        }
        function onSnapPreviewChanged(key, x, y, w, h, visible) {
            if (key !== root.windowKey)
                return
            snapPreview.hidePreview()
        }
        function onSnappedVisualChanged(key, snapped) {
            if (key === root.windowKey) {
                root.snappedVisual = snapped
                if (!snapped)
                    root.snappedVisualKind = ""
                else
                    root.scheduleSnappedVisualSync()
                root.snapShadowSuppressed = false
                customShadow.forceStackSync(2)
            }
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
            root.playTransition(frameRoot.width / 2, frameRoot.height / 2, mode)
        }
        function onPrimaryColorChanged(color) {
            // Pure QML color updates. Avoid native frame refresh while dragging the color wheel.
        }
    }

    Component.onCompleted: {
        if (bridge) {
            if (root.autoRestoreWindowState)
                bridge.window.restoreWindowState(root)
            bridge.window.installNativeFrame(root)
        }
    }

    onXChanged: requestSnappedVisualSync()
    onYChanged: requestSnappedVisualSync()
    onWidthChanged: {
        windowEvent("widthChanged", ({ "width": width }))
        if (root.windowKey === "main")
            resizeTrimTimer.restart()
        requestSnappedVisualSync()
    }
    onHeightChanged: {
        windowEvent("heightChanged", ({ "height": height }))
        if (root.windowKey === "main")
            resizeTrimTimer.restart()
        requestSnappedVisualSync()
    }
    onVisibilityChanged: {
        if (root.visibility !== Window.Windowed)
            root.snapShadowSuppressed = false
        requestSnappedVisualSync()
        chromeRefreshTimer.restart()
        windowEvent("visibilityChanged", ({ "visibility": root.visibility }))
    }
    onActiveChanged: {
        requestSnappedVisualSync()
        windowEvent("activeChanged", ({ "active": active }))
    }
    onClosing: function(close) {
        if (bridge)
            bridge.window.saveWindowState(root)
        snapPreview.hidePreview()
        if (bridge && bridge.tray && bridge.tray.handleClosing(root)) {
            close.accepted = false
            return
        }
        if (root.windowKey === "main" && bridge && bridge.dialogs)
            bridge.dialogs.shutdown()
        windowEvent("closing", ({}))
    }
}
