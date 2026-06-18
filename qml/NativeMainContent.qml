import QtQuick
import QtQuick.Controls
import QtQuick.Window
import FramelessNative 1.0
import "core" as Core
import "window"
import "layout"
import "controls"

Item {
    id: root
    implicitWidth: 936
    implicitHeight: 749

    readonly property real devicePixelRatio: Math.max(1.0, (root.Window.window && root.Window.window.screen) ? root.Window.window.screen.devicePixelRatio : Screen.devicePixelRatio)
    readonly property real physicalPixel: 1.0 / devicePixelRatio
    readonly property real stableHairline: Math.max(1.0, physicalPixel)
    function snapToPhysicalPixel(value) {
        return Math.round(value / physicalPixel) * physicalPixel
    }

    function savedNavLogicalWidth() {
        if (typeof App === "undefined" || !App || !App.settings)
            return 46
        const logicalWidth = Number(App.settings.valueOr("layout/navWidth", 46))
        if (logicalWidth <= 0)
            return 0
        return Math.max(0, Math.min(logicalWidth, 132))
    }

    property string windowKey: "main"
    property bool nativeMaximized: false
    property bool nativeSnapped: false
    property bool nativeCustomChrome: (typeof NativeHost !== "undefined" && NativeHost && NativeHost.customChromeEnabled !== undefined) ? NativeHost.customChromeEnabled : false
    property bool nativeCustomShadow: (typeof NativeHost !== "undefined" && NativeHost) ? NativeHost.customShadowEnabled : false
    property bool customSnapPreviewEnabled: false
    property int cornerRadius: (nativeMaximized || nativeSnapped) ? 0 : Core.Theme.radius.window
    property alias titleBar: titleBar
    property bool _localThemeAnimation: false
    property bool snapShadowSuppressed: false
    property bool nativeDragRestoreVisual: false
    property int normalShadowVisualInset: Core.Theme.dp(32)
    property bool nativeExternalShadow: root.nativeCustomShadow && Qt.platform.os === "windows"
    property bool inlineWindowsEnabled: true
    property string pendingTransitionMode: ""
    property real pendingTransitionX: 0
    property real pendingTransitionY: 0
    property color displaySurfaceColor: Core.Theme.color.surface
    property color displaySurfaceBorderColor: Core.Theme.color.outline
    property bool hostShellBackgroundAnimating: false
    property bool nativeSizeMoveActive: false
    property bool _closingMainWindow: false
    property string pendingInlinePageKey: ""
    property var pendingInlineProps: ({})
    property bool trayMenuVisible: false
    property alias nativeWidgetAgent: nativeWidgetHostAgent
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
        return Core.Theme.mode === "dark" ? 1.0 : 0.78
    }
    property bool inlineShadowVisible: root.nativeCustomShadow
                                       && !root.nativeExternalShadow
                                       && !root.nativeMaximized
                                       && !root.nativeSnapped
                                       && root.cornerRadius > 0
    property bool nativeExternalShadowEnabled: root.nativeExternalShadow
                                               && root.nativeCustomShadow
                                               && !root.nativeMaximized
                                               && !root.nativeSnapped
                                               && root.cornerRadius > 0
    property bool normalVisualMarginsActive: root.inlineShadowVisible
    property int shadowVisualInset: root.inlineShadowVisible ? root.normalShadowVisualInset : 0

    NativeWidgetHostAgent {
        id: nativeWidgetHostAgent
        filterEnabled: Qt.platform.os === "windows"
                       && typeof NativeHost !== "undefined"
                       && NativeHost
                       && NativeHost.nativeHwnd !== undefined
                       && NativeHost.nativeHwnd.length > 0
        hostHwnd: filterEnabled ? NativeHost.nativeHwnd : ""
        customShadowEnabled: root.nativeCustomShadow
        maximized: root.nativeMaximized
        fullScreen: false
        snapped: root.nativeSnapped
        resizeBorder: (typeof NativeHost !== "undefined" && NativeHost && NativeHost.resizeBorder !== undefined)
                      ? NativeHost.resizeBorder
                      : 5
        shadowInset: root.shadowVisualInset
        titleBarHeight: Math.round(titleBar.nativeTitleBarHeight)
        captionLeftA: Math.round(titleBar.nativeCaptionLeftA)
        captionRightA: Math.round(titleBar.nativeCaptionRightA)
        captionLeftB: Math.round(titleBar.nativeCaptionLeftB)
        captionRightB: Math.round(titleBar.nativeCaptionRightB)
        minimizeButtonRect: root.systemButtonRect(titleBar.minimizeButtonItem)
        maximizeButtonRect: root.systemButtonRect(titleBar.maximizeButtonItem)
        closeButtonRect: root.systemButtonRect(titleBar.closeButtonItem)
        Component.onCompleted: {
            nativeWidgetHostAgent.setShellBackgroundColor(root.displaySurfaceColor)
            if (typeof NativeHost !== "undefined" && NativeHost && NativeHost.setNativeWidgetAgentReady)
                NativeHost.setNativeWidgetAgentReady(filterEnabled)
            root.syncNativeCornerRadius()
            root.syncHostShellBackground(root.displaySurfaceColor)
            if (filterEnabled && typeof NativeHost !== "undefined" && NativeHost && NativeHost.refreshWindowsChrome)
                NativeHost.refreshWindowsChrome()
        }
        onFilterEnabledChanged: {
            if (typeof NativeHost !== "undefined" && NativeHost && NativeHost.setNativeWidgetAgentReady)
                NativeHost.setNativeWidgetAgentReady(filterEnabled)
            root.syncNativeCornerRadius()
            root.syncHostShellBackground(root.displaySurfaceColor)
            if (filterEnabled && typeof NativeHost !== "undefined" && NativeHost && NativeHost.refreshWindowsChrome)
                NativeHost.refreshWindowsChrome()
        }
        onSizingOrPositionChanging: {
            // 不要在这里反向调用 Python 去同步 QML 几何。
            // Win32 缩放消息尚未提交时抢跑会放大左上角缩放的右下边界牵引。
            root.syncNativeState(false)
        }
        onMoving: {
            if (typeof NativeHost !== "undefined" && NativeHost && NativeHost.handleNativeMoving)
                NativeHost.handleNativeMoving()
            root.syncNativeState(false)
        }
        onNativeSizeMoveStarted: {
            if (typeof App !== "undefined" && App && App.beginWindowInteraction)
                App.beginWindowInteraction()
            root.nativeSizeMoveActive = true
            if (typeof NativeHost !== "undefined" && NativeHost && NativeHost.setNativeSizeMoveActive)
                NativeHost.setNativeSizeMoveActive(true)
            root.syncNativeState(false)
        }
        onNativeSizeMoveFinished: {
            root.nativeSizeMoveActive = false
            if (typeof NativeHost !== "undefined" && NativeHost && NativeHost.setNativeSizeMoveActive)
                NativeHost.setNativeSizeMoveActive(false)
            root.syncNativeState()
            root.syncExternalShadow(true)
            if (typeof App !== "undefined" && App && App.endWindowInteraction)
                App.endWindowInteraction()
        }
        onWindowPositionChanged: {
            if (typeof NativeHost !== "undefined" && NativeHost && NativeHost.handleNativeWindowPosChanged)
                NativeHost.handleNativeWindowPosChanged()
            root.syncNativeState()
        }
    }

    ExternalShadowController {
        id: externalShadow
    }

    function showToast(message) {
        toastModel.append({ "message": message, "createdAt": Date.now() })
        while (toastModel.count > 5)
            toastModel.remove(0)
    }

    function changeThemeWithRipple(nextMode, px, py) {
        if (nextMode !== "dark" && nextMode !== "light")
            return
        if (nextMode === Core.Theme.mode)
            return
        root._localThemeAnimation = true
        root.transitionSurfaceForMode(nextMode)
        if (App && App.theme && App.theme.setRippleOrigin)
            App.theme.setRippleOrigin(px === undefined ? frameRoot.width / 2 : px,
                                      py === undefined ? frameRoot.height / 2 : py)
        NativeHost.changeThemeWithRipple(nextMode,
                                         px === undefined ? frameRoot.width / 2 : px,
                                         py === undefined ? frameRoot.height / 2 : py)
    }

    function playTransition(cx, cy, mode) {
        pendingTransitionX = cx
        pendingTransitionY = cy
        pendingTransitionMode = mode
    }

    function transitionSurfaceColor(nextColor, nextBorderColor) {
        const oldColor = background.color
        hostShellBackgroundAnimating = true
        displaySurfaceColor = nextColor
        displaySurfaceBorderColor = nextBorderColor === undefined ? Core.Theme.color.outline : nextBorderColor
        root.animateHostShellBackground(oldColor, nextColor)
        hostShellBackgroundAnimating = false
    }

    function commitSurfaceColor(nextColor, nextBorderColor) {
        displaySurfaceColor = nextColor
        displaySurfaceBorderColor = nextBorderColor === undefined ? Core.Theme.color.outline : nextBorderColor
        root.syncHostShellBackground(nextColor)
    }

    function transitionSurfaceForMode(nextMode) {
        root.transitionSurfaceColor(Core.Theme.previewColor("surface", nextMode),
                                    Core.Theme.previewColor("outline", nextMode))
    }

    function commitSurfaceForMode(nextMode) {
        root.commitSurfaceColor(Core.Theme.previewColor("surface", nextMode),
                                Core.Theme.previewColor("outline", nextMode))
    }

    function syncHostShellBackground(color) {
        if (typeof NativeHost !== "undefined" && NativeHost && NativeHost.setShellBackgroundColor)
            NativeHost.setShellBackgroundColor(color)
        nativeWidgetHostAgent.setShellBackgroundColor(color)
    }

    function animateHostShellBackground(fromColor, toColor) {
        if (typeof NativeHost !== "undefined" && NativeHost && NativeHost.animateShellBackgroundColor)
            NativeHost.animateShellBackgroundColor(fromColor, toColor, Core.Theme.animatedColorTransitionMs)
        else
            root.syncHostShellBackground(toColor)
        nativeWidgetHostAgent.setShellBackgroundColor(toColor)
    }

    function syncNativeHitTestMetrics() {
        if (typeof NativeHost === "undefined" || !NativeHost || !NativeHost.setTitleBarHitTestMetrics)
            return
        NativeHost.setTitleBarHitTestMetrics(
            Math.round(titleBar.nativeTitleBarHeight),
            Math.round(titleBar.nativeCaptionLeftA),
            Math.round(titleBar.nativeCaptionRightA),
            Math.round(titleBar.nativeCaptionLeftB),
            Math.round(titleBar.nativeCaptionRightB)
        )
    }

    function systemButtonRect(item) {
        if (!item || !item.visible)
            return ({})
        const p = item.mapToItem(frameRoot, 0, 0)
        return ({
            "x": Math.round(p.x),
            "y": Math.round(p.y),
            "width": Math.round(item.width),
            "height": Math.round(item.height)
        })
    }

    function syncNativeCornerRadius() {
        if (typeof NativeHost === "undefined" || !NativeHost || !NativeHost.setCornerRadius)
            return
        NativeHost.setCornerRadius(root.cornerRadius)
    }

    function nativeHwndText() {
        if (typeof NativeHost === "undefined" || !NativeHost || NativeHost.nativeHwnd === undefined)
            return ""
        return String(NativeHost.nativeHwnd || "")
    }

    function cleanupExternalShadow() {
        if (!externalShadow || !externalShadow.destroyNativeShadowForHwnd)
            return
        const hwnd = root.nativeHwndText()
        if (hwnd.length <= 0)
            return
        externalShadow.destroyNativeShadowForHwnd(hwnd)
    }

    function requestMainClose() {
        if (typeof App !== "undefined" && App && App.tray && App.tray.handleClosing(NativeHost))
            return
        root._closingMainWindow = true
        if (typeof App !== "undefined" && App && App.exitApplication)
            App.exitApplication()
        else if (typeof NativeHost !== "undefined" && NativeHost)
            NativeHost.closeWindow()
    }

    function fadeOutExternalShadow() {
        if (!externalShadow || !externalShadow.fadeOutNativeShadowForHwnd)
            return
        const hwnd = root.nativeHwndText()
        if (hwnd.length <= 0)
            return
        externalShadow.fadeOutNativeShadowForHwnd(hwnd)
    }

    function syncExternalShadow(forceRepaint) {
        if (root._closingMainWindow)
            return
        if (!externalShadow || !externalShadow.setNativeShadowForHwnd)
            return
        const hwnd = root.nativeHwndText()
        if (hwnd.length <= 0)
            return
        if (root.nativeExternalShadow) {
            // 阴影是独立 helper HWND，只跟随主 HWND；不要用它修主窗口 live resize 黑底。
            externalShadow.setNativeShadowForHwnd(hwnd,
                                                  root.nativeExternalShadowEnabled,
                                                  Qt.resolvedUrl("../resources/images/window_shadow.png"),
                                                  root.externalShadowMargin,
                                                  root.externalShadowOpacity,
                                                  root.cornerRadius,
                                                  root.displaySurfaceColor)
            if (forceRepaint && root.nativeExternalShadowEnabled && externalShadow.syncNativeShadowForHwnd)
                externalShadow.syncNativeShadowForHwnd(hwnd)
        } else {
            externalShadow.destroyNativeShadowForHwnd(hwnd)
        }
    }

    function syncNativeState(updateShadow) {
        if (typeof NativeHost === "undefined" || !NativeHost)
            return
        root.nativeMaximized = NativeHost.isMaximizedState()
        root.nativeSnapped = NativeHost.isSnappedState()
        root.syncNativeCornerRadius()
        if (updateShadow !== false && !root.nativeSizeMoveActive)
            root.syncExternalShadow(false)
        if (root.nativeMaximized || root.nativeSnapped)
            root.snapShadowSuppressed = false
    }

    function toggleMaximizedPrepared() {
        if (typeof NativeHost === "undefined" || !NativeHost)
            return
        const wasMaximized = NativeHost.isMaximizedState()
        const wasSnapped = NativeHost.isSnappedState()
        if (!wasMaximized && !wasSnapped)
            root.fadeOutExternalShadow()
        if (typeof App !== "undefined" && App && App.beginWindowInteraction)
            App.beginWindowInteraction()
        NativeHost.toggleMaximized()
        if (typeof App !== "undefined" && App && App.endWindowInteractionSoon)
            App.endWindowInteractionSoon()
    }

    function adjustFontScaleByWheel(deltaY) {
        if (typeof App === "undefined" || !App || !App.theme)
            return
        if (deltaY > 0)
            App.theme.increaseFontScale()
        else if (deltaY < 0)
            App.theme.decreaseFontScale()
    }

    function childTitleFor(pageKey) {
        return Core.AppInfo.pageTitle(pageKey)
    }

    function savedCurrentPage() {
        if (typeof App === "undefined" || !App || !App.settings)
            return "home"
        const page = String(App.settings.valueOr("ui/lastPage", "home") || "home")
        return Core.AppInfo.pageSource(page).length > 0 ? page : "home"
    }

    function showMainPage(pageKey, persist) {
        const page = Core.AppInfo.pageSource(pageKey).length > 0 ? String(pageKey) : "home"
        sideNav.currentPage = page
        pageHost.showPage(page)
        if (persist && typeof App !== "undefined" && App && App.settings)
            App.settings.setValue("ui/lastPage", page)
    }

    function openChildByPolicy(pageKey, props, mode) {
        const openMode = mode || "auto"
        const lowMemory = (typeof App !== "undefined" && App && App.performance) ? App.performance.effectiveProfile === "low-memory" : false
        const useInline = root.inlineWindowsEnabled && (openMode === "inline" || (openMode === "auto" && lowMemory))
        if (useInline) {
            const safeProps = props || ({})
            if (inlineWindowManagerLoader.item) {
                inlineWindowManagerLoader.item.openPage(pageKey, childTitleFor(pageKey), safeProps)
            } else {
                pendingInlinePageKey = String(pageKey || "about")
                pendingInlineProps = safeProps
                inlineWindowManagerLoader.active = true
            }
        } else if (typeof App !== "undefined" && App && App.dialogs) {
            App.dialogs.openChild(NativeHost, pageKey, props || ({}))
        }
    }

    function prepareOpenChildByPolicy(pageKey, mode) {
        const openMode = mode || "auto"
        const lowMemory = (typeof App !== "undefined" && App && App.performance) ? App.performance.effectiveProfile === "low-memory" : false
        const useInline = root.inlineWindowsEnabled && (openMode === "inline" || (openMode === "auto" && lowMemory))
        if (useInline) {
            inlineWindowManagerLoader.active = true
        } else if (typeof App !== "undefined" && App && App.dialogs && App.dialogs.prepareChild) {
            App.dialogs.prepareChild(pageKey)
        }
    }

    ShadowWindow {
        id: customShadow
        targetWindow: null
        targetX: (typeof NativeHost !== "undefined" && NativeHost) ? NativeHost.shadowX : 0
        targetY: (typeof NativeHost !== "undefined" && NativeHost) ? NativeHost.shadowY : 0
        targetWidth: (typeof NativeHost !== "undefined" && NativeHost) ? NativeHost.shadowWidth : 0
        targetHeight: (typeof NativeHost !== "undefined" && NativeHost) ? NativeHost.shadowHeight : 0
        stackController: (typeof App !== "undefined" && App && App.window) ? App.window : null
        shadowEnabled: false
        cornerRadius: root.cornerRadius
    }

    Rectangle {
        id: background
        anchors.fill: frameRoot
        radius: root.cornerRadius
        antialiasing: true
        color: root.displaySurfaceColor
        border.color: (root.nativeMaximized || root.nativeSizeMoveActive) ? "transparent" : root.displaySurfaceBorderColor
        border.width: (root.nativeMaximized || root.nativeSizeMoveActive) ? 0 : root.stableHairline
        z: 0.5
        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
        Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
        Behavior on radius { NumberAnimation { duration: (root.nativeMaximized || root.nativeSnapped) ? 0 : 80; easing.type: Easing.OutCubic } }
    }

    BorderImage {
        id: inlineShadow
        anchors.fill: parent
        visible: root.inlineShadowVisible || opacity > 0.001
        source: "../resources/images/window_shadow.png"
        border.left: root.shadowVisualInset
        border.top: root.shadowVisualInset
        border.right: root.shadowVisualInset
        border.bottom: root.shadowVisualInset
        horizontalTileMode: BorderImage.Stretch
        verticalTileMode: BorderImage.Stretch
        smooth: false
        cache: true
        opacity: root.inlineShadowVisible ? (Core.Theme.mode === "dark" ? 1.0 : 0.78) : 0
        z: 0
        Behavior on opacity {
            NumberAnimation {
                duration: 0
                easing.type: Easing.OutCubic
            }
        }
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
        anchors.fill: parent
        anchors.margins: root.shadowVisualInset
        clip: true
        z: 1

        Item {
            id: mainColumn
            anchors.fill: parent
            z: 2

            TitleBar {
                id: titleBar
                y: 0
                z: 2
                width: parent.width
                height: Core.Theme.metrics.titleBarHeight
                windowTitle: Core.AppInfo.windowTitle
                frameRadius: root.cornerRadius
                alwaysOnTop: (typeof NativeHost !== "undefined" && NativeHost) ? NativeHost.alwaysOnTop : false
                showNavToggle: true
                showColorButton: Core.Theme.showColorButton
                windowMaximized: root.nativeMaximized
                useNativeCaption: Qt.platform.os === "windows"
                leftMenus: Core.AppInfo.mainMenus

                onActivateRequested: NativeHost.activateHost()
                onMoveRequested: function(localX, localY) { NativeHost.activateHost(); NativeHost.beginSystemMove(localX, localY) }
                onMoveUpdated: NativeHost.updateSystemMove()
                onMoveFinished: NativeHost.endSystemMove()
                onToggleMaximizeRequested: root.toggleMaximizedPrepared()
                onMinimizeRequested: NativeHost.showMinimizedNative()
                onCloseRequested: root.requestMainClose()
                onThemeToggleRequested: function(localPos, nextMode) { root.changeThemeWithRipple(nextMode, localPos.x, localPos.y) }
                onAlwaysOnTopRequested: function(enabled) { NativeHost.setAlwaysOnTop(enabled) }
                onToggleNavRequested: sideNav.toggle()
                onNativeTitleBarHeightChanged: Qt.callLater(root.syncNativeHitTestMetrics)
                onNativeCaptionLeftAChanged: Qt.callLater(root.syncNativeHitTestMetrics)
                onNativeCaptionRightAChanged: Qt.callLater(root.syncNativeHitTestMetrics)
                onNativeCaptionLeftBChanged: Qt.callLater(root.syncNativeHitTestMetrics)
                onNativeCaptionRightBChanged: Qt.callLater(root.syncNativeHitTestMetrics)
                onMinimizeButtonItemChanged: Qt.callLater(root.syncNativeHitTestMetrics)
                onMaximizeButtonItemChanged: Qt.callLater(root.syncNativeHitTestMetrics)
                onCloseButtonItemChanged: Qt.callLater(root.syncNativeHitTestMetrics)
                onMenuActionRequested: function(action, kind) {
                    if (kind === "page") {
                        root.showMainPage(action, true)
                    } else {
                        root.openChildByPolicy(action, ({}), "auto")
                    }
                }
                onMenuActionPrepared: function(action, kind) {
                    if (kind !== "child")
                        return
                    if (typeof App !== "undefined" && App && App.dialogs && App.dialogs.prepareChild)
                        App.dialogs.prepareChild(action)
                }
            }

            Row {
                id: mainRow
                y: titleBar.height
                z: 1
                width: parent.width
                height: Math.max(0, parent.height - titleBar.height)

                ResizableSideNav {
                    id: sideNav
                    height: parent.height
                    logicalWidth: root.savedNavLogicalWidth()
                    cornerRadius: root.cornerRadius
                    currentPage: root.savedCurrentPage()
                    onPageIntent: function(page) { pageHost.preparePage(page) }
                    onCurrentPageChanged: root.showMainPage(currentPage, true)
                }

                PageHost {
                    id: pageHost
                    width: Math.max(0, Math.round(parent.width - sideNav.width))
                    height: parent.height
                }
            }

            Loader {
                id: inlineWindowManagerLoader
                x: Math.round(mainRow.x + sideNav.width)
                y: mainRow.y
                width: Math.round(pageHost.width)
                height: pageHost.height
                z: 10
                active: false
                sourceComponent: InlineWindowManager {
                    width: inlineWindowManagerLoader.width
                    height: inlineWindowManagerLoader.height
                }
                onLoaded: {
                    if (item && root.pendingInlinePageKey.length > 0) {
                        const key = root.pendingInlinePageKey
                        const props = root.pendingInlineProps || ({})
                        root.pendingInlinePageKey = ""
                        root.pendingInlineProps = ({})
                        item.openPage(key, root.childTitleFor(key), props)
                    }
                }
            }

            Connections {
                target: inlineWindowManagerLoader.item
                function onWindowCountChanged() {
                    if (!inlineWindowManagerLoader.item || inlineWindowManagerLoader.item.windowCount !== 0)
                        return
                    Qt.callLater(function() {
                        if (inlineWindowManagerLoader.item && inlineWindowManagerLoader.item.windowCount === 0) {
                            inlineWindowManagerLoader.active = false
                            if (typeof App !== "undefined" && App && App.trimMemoryAfterInlineWindowsClosed)
                                Qt.callLater(App.trimMemoryAfterInlineWindowsClosed)
                        }
                    })
                }
            }
        }

        Rectangle {
            id: windowEdgeOverlay
            anchors.fill: parent
            anchors.margins: root.stableHairline
            z: 90
            visible: !root.nativeSizeMoveActive
            radius: Math.max(0, root.cornerRadius - root.stableHairline)
            color: "transparent"
            border.color: root.cornerRadius > 0 ? Core.Theme.color.windowEdge : "transparent"
            border.width: (root.cornerRadius > 0 && !root.nativeSizeMoveActive) ? root.stableHairline * 1.15 : 0
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

    }

    SnapPreviewWindow {
        id: snapPreview
        transientParent: root.Window.window
    }

    Binding { target: titleBar; property: "navHidden"; value: sideNav.width === 0 }

    Timer {
        id: resizeTrimTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (typeof App !== "undefined" && App && App.trimResizeMemory)
                App.trimResizeMemory()
            else if (typeof App !== "undefined" && App && App.trimMemory)
                App.trimMemory()
        }
    }

    function smokeShowPage(pageKey) {
        if (!pageKey || pageKey.length <= 0)
            return false
        root.showMainPage(String(pageKey), true)
        return true
    }

    onWidthChanged: {
        Qt.callLater(root.syncNativeHitTestMetrics)
        resizeTrimTimer.restart()
    }
    onHeightChanged: {
        Qt.callLater(root.syncNativeHitTestMetrics)
        resizeTrimTimer.restart()
    }

    Connections {
        target: NativeHost
        function onToastRequested(message) { root.showToast(message) }
        function onMaximizedChanged() {
            root.syncNativeState()
        }
        function onGeometryChanged() {
            root.syncNativeState()
        }
        function onNativeShown() {
            root.syncNativeState()
            root.syncExternalShadow(true)
        }
        function onSnapPreviewChanged(key, x, y, w, h, visible) {
            if (key !== root.windowKey)
                return
            if (!root.customSnapPreviewEnabled) {
                snapPreview.hidePreview()
                return
            }
            if (visible)
                snapPreview.showAt(Qt.rect(x, y, w, h))
            else
                snapPreview.hidePreview()
        }
    }

    Connections {
        target: App && App.theme ? App.theme : null
        function onModeChanged(mode) {
            root.syncExternalShadow(true)
            if (root._localThemeAnimation) {
                root._localThemeAnimation = false
                return
            }
            root.transitionSurfaceForMode(mode)
        }
        function onPrimaryColorChanged(color) {
            root.commitSurfaceColor(Core.Theme.color.surface, Core.Theme.color.outline)
        }
    }

    Connections {
        target: (typeof App !== "undefined" && App && App.tray) ? App.tray : null
        function onTrayPrimaryClicked() {
            if (App && App.tray)
                App.tray.centerMainWindow()
        }
    }

    Connections {
        target: Core.InlineWindowBus
        function onPrepareChildRequested(pageKey, mode) {
            root.prepareOpenChildByPolicy(pageKey, mode)
        }
        function onOpenChildRequested(pageKey, mode, props) {
            root.openChildByPolicy(pageKey, props, mode)
        }
    }

    Connections {
        target: (typeof App !== "undefined" && App) ? App : null
        function onPrepareChildRequested(pageKey, mode) {
            root.prepareOpenChildByPolicy(pageKey, mode)
        }
        function onOpenChildRequested(pageKey, mode, props) {
            root.openChildByPolicy(pageKey, props, mode)
        }
    }

    Component.onCompleted: {
        root.commitSurfaceColor(Core.Theme.color.surface, Core.Theme.color.outline)
        root.syncNativeState()
        if (App && App.tray)
            App.tray.registerWindow(NativeHost)
        root.showMainPage(sideNav.currentPage, false)
        Qt.callLater(root.syncNativeHitTestMetrics)
    }
    Component.onDestruction: {
        // Main-window shutdown should let the process/window system tear down
        // the helper together with the window. Destroying it here makes the
        // external shadow disappear one frame earlier than the main window.
        if (root.windowKey !== "main")
            root.cleanupExternalShadow()
    }
    onCornerRadiusChanged: {
        if (root._closingMainWindow)
            return
        root.syncNativeCornerRadius()
        root.syncExternalShadow(true)
    }
    onNativeCustomShadowChanged: if (!root._closingMainWindow) root.syncExternalShadow(true)
    onNativeExternalShadowChanged: if (!root._closingMainWindow) root.syncExternalShadow(true)
    onNativeExternalShadowEnabledChanged: if (!root._closingMainWindow) root.syncExternalShadow(true)
    onExternalShadowMarginChanged: if (!root._closingMainWindow) root.syncExternalShadow(true)
    onExternalShadowOpacityChanged: if (!root._closingMainWindow) root.syncExternalShadow(true)
    onDisplaySurfaceColorChanged: {
        if (!root.hostShellBackgroundAnimating)
            root.syncHostShellBackground(root.displaySurfaceColor)
    }
}

