import QtQuick
import QtQuick.Window
import "../core" as Core

QtObject {
    id: root

    property var windowRoot
    property var nativeAgent
    property bool enabled: false
    property bool windowMaximized: false
    property bool snappedVisual: false
    property int externalShadowMargin: 0
    property int cornerRadius: 0
    property color surfaceColor: "transparent"
    property real physicalPixel: 1.0

    property bool pendingStateSync: false
    property bool windowStateTransition: false
    property bool dprTransition: false
    property bool applyingInsetGeometry: false
    property int appliedShadowInset: 0

    readonly property bool shadowVisible: enabled
                                       && windowRoot
                                       && windowRoot.customShadowEnabled
                                       && cornerRadius > 0
                                       && !dprTransition
    readonly property bool interactiveCaptionMode: enabled
    readonly property int shadowInset: (enabled && !windowMaximized && !snappedVisual)
                                       ? externalShadowMargin
                                       : 0
    readonly property real snappedShadowInset: snapToPhysicalPixel(shadowInset)
    readonly property int windowStateGeometryInset: enabled ? Math.round(shadowInset) : 0
    readonly property color shellBackgroundColor: {
        if (enabled && windowStateTransition)
            return surfaceColor
        if (enabled)
            return shadowInset > 0 ? "transparent" : surfaceColor
        return surfaceColor
    }

    readonly property color shellBackgroundForWindow: enabled ? shellBackgroundColor : "transparent"

    onShadowInsetChanged: handleShadowInsetChanged()

    function linuxCsdShadowDisabled() {
        if (typeof App === "undefined" || !App || !App.envValue)
            return false
        const value = String(App.envValue("QROUNDEDFRAME_DISABLE_LINUX_CSD_SHADOW") || "").toLowerCase()
        return value === "1" || value === "true" || value === "yes" || value === "on"
    }

    function snapToPhysicalPixel(value) {
        const px = Math.max(0.0001, physicalPixel)
        return Math.round(value / px) * px
    }

    function syncNativeShellBackground() {
        if (nativeAgent && nativeAgent.setShellBackgroundColor)
            nativeAgent.setShellBackgroundColor(shellBackgroundColor)
    }

    function preRegisterNativeChrome() {
        applyNativeMode()
    }

    function postRegisterNativeChrome() {
        syncGtkFrameExtents()
    }

    function applyNativeMode() {
        if (nativeAgent && nativeAgent.setClientSideShadowMode)
            nativeAgent.setClientSideShadowMode(enabled)
    }

    function syncGtkFrameExtents() {
        if (!nativeAgent || !nativeAgent.setGtkFrameExtents)
            return
        const inset = enabled && !windowStateTransition
                    ? snapToPhysicalPixel(shadowInset)
                    : 0
        nativeAgent.setGtkFrameExtents(inset, inset, inset, inset)
    }

    function applyShadowInset() {
        if (!enabled)
            return
        const nextInset = shadowInset
        if (nextInset === appliedShadowInset || applyingInsetGeometry)
            return
        applyingInsetGeometry = true
        appliedShadowInset = nextInset
        applyingInsetGeometry = false
        syncGtkFrameExtents()
    }

    function scheduleStateSync() {
        if (!enabled) {
            if (windowRoot && windowRoot.syncNativeWindowState)
                windowRoot.syncNativeWindowState()
            return
        }
        if (pendingStateSync)
            return
        pendingStateSync = true
        Qt.callLater(function() {
            pendingStateSync = false
            if (!windowRoot)
                return
            windowRoot.syncNativeWindowState()
            if (nativeAgent && nativeAgent.setCornerRadius)
                nativeAgent.setCornerRadius(cornerRadius)
            syncGtkFrameExtents()
            syncNativeShellBackground()
        })
    }

    function beginDprTransition() {
        if (!enabled)
            return
        dprTransition = true
        applyShadowInset()
        syncGtkFrameExtents()
        if (nativeAgent && nativeAgent.setCornerRadius)
            nativeAgent.setCornerRadius(cornerRadius)
        syncNativeShellBackground()
    }

    function finishDprTransition() {
        if (!enabled || !dprTransition)
            return
        dprTransition = false
        syncGtkFrameExtents()
        syncNativeShellBackground()
    }

    function handleNativeSystemMoveFinished() {
        if (!enabled || !windowRoot)
            return
        if (windowRoot.titleBarControl)
            windowRoot.titleBarControl.resetDragState()
        windowStateTransition = false
        windowRoot.syncNativeWindowState()
        windowRoot.windowMaximized = false
        syncGtkFrameExtents()
        if (windowRoot.markNativeShadowDisplayReady)
            windowRoot.markNativeShadowDisplayReady()
        syncNativeShellBackground()
    }

    function beginWindowStateTransition() {
        if (!enabled)
            return
        windowStateTransition = true
        syncGtkFrameExtents()
        syncNativeShellBackground()
    }

    function finishWindowStateTransition() {
        if (!enabled)
            return
        windowStateTransition = false
        syncGtkFrameExtents()
        syncNativeShellBackground()
    }

    function handleToggleMaximized(wasMaximized) {
        if (!enabled || !windowRoot)
            return
        beginWindowStateTransition()
        if (wasMaximized)
            windowRoot.showNormal()
        else
            windowRoot.showMaximized()
        Qt.callLater(function() {
            if (!windowRoot)
                return
            windowRoot.syncNativeWindowState()
            if (nativeAgent && nativeAgent.setCornerRadius)
                nativeAgent.setCornerRadius(cornerRadius)
            finishWindowStateTransition()
        })
    }

    function tryStartTitleBarMove(snappedVisual) {
        if (!enabled || !windowRoot || !nativeAgent || !nativeAgent.startSystemMove || snappedVisual)
            return false
        return nativeAgent.startSystemMove(windowRoot)
    }

    function beginFallbackMove(localX, localY) {
        if (!enabled || !windowRoot || !windowRoot.bridge || !windowRoot.bridge.window)
            return
        windowRoot.bridge.window.beginMove(windowRoot, localX, localY)
    }

    function updateFallbackMove() {
        if (!enabled || !windowRoot || !windowRoot.bridge || !windowRoot.bridge.window)
            return
        windowRoot.bridge.window.updateMove(windowRoot)
    }

    function endFallbackMove() {
        if (!enabled || !windowRoot || !windowRoot.bridge || !windowRoot.bridge.window)
            return
        windowRoot.bridge.window.endMove(windowRoot)
    }

    function handleVisibilityChanged(nativeSystemMoveFromMaximized) {
        if (!windowRoot)
            return
        if (enabled && nativeSystemMoveFromMaximized) {
            windowRoot.syncNativeWindowState()
            if (nativeAgent && nativeAgent.setCornerRadius)
                nativeAgent.setCornerRadius(cornerRadius)
            syncGtkFrameExtents()
            syncNativeShellBackground()
        }
        scheduleStateSync()
    }

    function resizeAreaEnabled(visibility, snappedVisualValue) {
        return interactiveCaptionMode
            && visibility !== Window.Maximized
            && visibility !== Window.FullScreen
            && !snappedVisualValue
    }

    function handleCornerRadiusChanged() {
        if (!enabled)
            return
        syncGtkFrameExtents()
    }

    function handleShadowInsetChanged() {
        if (!enabled)
            return
        applyShadowInset()
        syncGtkFrameExtents()
        syncNativeShellBackground()
    }

    Component.onCompleted: {
        if (!nativeAgent)
            return
        nativeAgent.onNativeSystemMoveFinished.connect(root.handleNativeSystemMoveFinished)
        nativeAgent.onEffectiveDevicePixelRatioChanged.connect(root.beginDprTransition)
        Screen.onDevicePixelRatioChanged.connect(root.beginDprTransition)
        Core.Theme.onContentControlScaleChanged.connect(root.beginDprTransition)
    }
}
