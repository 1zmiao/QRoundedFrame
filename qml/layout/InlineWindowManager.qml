import QtQuick
import "../core" as Core
import "../window"

Item {
    id: root

    property var windowsByKey: ({})
    property int windowCount: 0
    property int zCounter: 100
    property var activeMoveWindow: null
    property real activeMoveAnchorX: 0
    property real activeMoveAnchorY: 0
    property real activeMovePressX: 0
    property real activeMovePressY: 0
    property bool activeMoveMoved: false
    property bool activeMoveWasMinimized: false
    property var activeResizeWindow: null
    property string activeResizeMode: ""
    property real activeResizePressX: 0
    property real activeResizePressY: 0
    property real activeResizeStartX: 0
    property real activeResizeStartY: 0
    property real activeResizeStartWidth: 0
    property real activeResizeStartHeight: 0
    property bool resizePressConsumed: false
    property bool nativeInlineMoveAvailable: nativeMoveLoader.status === Loader.Ready
    property bool nativeInlineMoveFailed: false
    readonly property int dockGap: Core.Theme.dp(8)
    readonly property int dockWidth: Core.Theme.dp(190)
    readonly property int dockHeight: Core.Theme.dp(36)

    clip: false
    visible: windowCount > 0
    enabled: visible

    function refreshWindowCount() {
        windowCount = Object.keys(windowsByKey).length
    }

    function requestWorkspaceGrowth(left, top, right, bottom) {
        // Inline windows no longer resize the native main window.
    }

    function endWorkspaceGrowth() {
        // Kept as a compatibility no-op for InlineChildWindow.
    }

    function moveWindowAt(mx, my) {
        var best = null
        var bestZ = -1
        const keys = Object.keys(windowsByKey)
        for (var i = 0; i < keys.length; ++i) {
            const obj = windowsByKey[keys[i]]
            if (!obj || !obj.visible)
                continue
            if (obj.minimized) {
                if (mx < obj.x || mx > obj.x + obj.width || my < obj.y || my > obj.y + obj.height)
                    continue
            } else {
                const edgeReserve = Core.Theme.dp(12)
                const controlsReserve = Core.Theme.dp(78)
                if (mx < obj.x + edgeReserve || mx > obj.x + obj.width - controlsReserve)
                    continue
                if (my < obj.y + edgeReserve || my > obj.y + Core.Theme.metrics.titleBarHeight)
                    continue
            }
            if (obj.z > bestZ) {
                best = obj
                bestZ = obj.z
            }
        }
        return best
    }

    function topWindowAtPoint(mx, my, includeMinimized) {
        var best = null
        var bestZ = -1
        const keys = Object.keys(windowsByKey)
        for (var i = 0; i < keys.length; ++i) {
            const obj = windowsByKey[keys[i]]
            if (!obj || !obj.visible)
                continue
            if (obj.minimized && !includeMinimized)
                continue
            if (mx < obj.x || mx > obj.x + obj.width || my < obj.y || my > obj.y + obj.height)
                continue
            if (obj.z > bestZ) {
                best = obj
                bestZ = obj.z
            }
        }
        return best
    }

    function isTopWindowAt(obj, mx, my, includeMinimized) {
        return obj && topWindowAtPoint(mx, my, includeMinimized) === obj
    }

    function resizeHit(mx, my) {
        const edge = Core.Theme.dp(4)
        const corner = Core.Theme.dp(9)
        var top = null
        var topZ = -1
        const keys = Object.keys(windowsByKey)
        for (var i = 0; i < keys.length; ++i) {
            const obj = windowsByKey[keys[i]]
            if (!obj || obj.minimized || !obj.visible)
                continue
            if (mx < obj.x || mx > obj.x + obj.width || my < obj.y || my > obj.y + obj.height)
                continue
            if (obj.z > topZ) {
                top = obj
                topZ = obj.z
            }
        }
        if (!top)
            return { "window": null, "mode": "" }

        const lx = mx - top.x
        const ly = my - top.y
        var mode = ""
        if (lx <= corner && ly <= corner)
            mode = "left-top"
        else if (lx >= top.width - corner && ly <= corner)
            mode = "right-top"
        else if (lx <= corner && ly >= top.height - corner)
            mode = "left-bottom"
        else if (lx >= top.width - corner && ly >= top.height - corner)
            mode = "right-bottom"
        else if (lx <= edge)
            mode = "left"
        else if (lx >= top.width - edge)
            mode = "right"
        else if (ly <= edge)
            mode = "top"
        else if (ly >= top.height - edge)
            mode = "bottom"
        if (mode.length > 0)
            return { "window": top, "mode": mode }
        return { "window": null, "mode": "" }
    }

    function cursorForResizeMode(mode) {
        if (mode === "left" || mode === "right")
            return Qt.SizeHorCursor
        if (mode === "top" || mode === "bottom")
            return Qt.SizeVerCursor
        if (mode === "left-top" || mode === "right-bottom")
            return Qt.SizeFDiagCursor
        if (mode === "right-top" || mode === "left-bottom")
            return Qt.SizeBDiagCursor
        return Qt.ArrowCursor
    }

    function beginTopLevelResize(obj, mode, mx, my) {
        if (!obj || mode.length === 0)
            return false
        raiseWindow(obj.pageKey)
        activeResizeWindow = obj
        activeResizeMode = mode
        activeResizePressX = mx
        activeResizePressY = my
        activeResizeStartX = obj.x
        activeResizeStartY = obj.y
        activeResizeStartWidth = obj.width
        activeResizeStartHeight = obj.height
        obj.moving = false
        return true
    }

    function updateTopLevelResize(mx, my) {
        if (!activeResizeWindow)
            return
        const dx = mx - activeResizePressX
        const dy = my - activeResizePressY
        var nx = activeResizeStartX
        var ny = activeResizeStartY
        var nw = activeResizeStartWidth
        var nh = activeResizeStartHeight
        if (activeResizeMode.indexOf("right") >= 0)
            nw = activeResizeStartWidth + dx
        if (activeResizeMode.indexOf("bottom") >= 0)
            nh = activeResizeStartHeight + dy
        if (activeResizeMode.indexOf("left") >= 0) {
            nw = activeResizeStartWidth - dx
            nx = activeResizeStartX + dx
        }
        if (activeResizeMode.indexOf("top") >= 0) {
            nh = activeResizeStartHeight - dy
            ny = activeResizeStartY + dy
        }
        if (nw < activeResizeWindow.minWindowWidth) {
            if (activeResizeMode.indexOf("left") >= 0)
                nx = activeResizeStartX + activeResizeStartWidth - activeResizeWindow.minWindowWidth
            nw = activeResizeWindow.minWindowWidth
        }
        if (nh < activeResizeWindow.minWindowHeight) {
            if (activeResizeMode.indexOf("top") >= 0)
                ny = activeResizeStartY + activeResizeStartHeight - activeResizeWindow.minWindowHeight
            nh = activeResizeWindow.minWindowHeight
        }
        activeResizeWindow.x = nx
        activeResizeWindow.y = ny
        activeResizeWindow.width = nw
        activeResizeWindow.height = nh
    }

    function endTopLevelResize() {
        activeResizeWindow = null
        activeResizeMode = ""
    }

    function beginTopLevelMove(obj, mx, my) {
        if (!obj)
            return false
        raiseWindow(obj.pageKey)
        activeMoveWindow = obj
        activeMoveAnchorX = mx - obj.x
        activeMoveAnchorY = my - obj.y
        activeMovePressX = mx
        activeMovePressY = my
        activeMoveMoved = false
        activeMoveWasMinimized = obj.minimized
        obj.moving = true
        return true
    }

    function updateTopLevelMove(mx, my) {
        if (!activeMoveWindow)
            return
        const dx = mx - activeMovePressX
        const dy = my - activeMovePressY
        activeMoveMoved = true
        activeMoveWindow.x = mx - activeMoveAnchorX
        activeMoveWindow.y = my - activeMoveAnchorY
        if (activeMoveWindow.minimized)
            activeMoveWindow.clampPositionOnly()
    }

    function endTopLevelMove() {
        if (activeMoveWindow) {
            if (activeMoveWasMinimized && !activeMoveMoved)
                restorePage(activeMoveWindow.pageKey)
            activeMoveWindow.moving = false
        }
        activeMoveWindow = null
        activeMoveMoved = false
        activeMoveWasMinimized = false
    }

    function pageSourceFor(page) {
        return Core.AppInfo.pageSource(page)
    }

    function titleFor(page, fallbackTitle) {
        if (fallbackTitle && String(fallbackTitle).length > 0)
            return String(fallbackTitle)
        return Core.AppInfo.pageTitle(page)
    }

    function openPage(pageKey, title, props) {
        const page = String(pageKey || "about")
        const safeProps = props || ({})
        const key = page === "task-edit" && safeProps.taskId !== undefined
                    ? page + "-" + String(safeProps.taskId)
                    : page
        const existing = windowsByKey[key]
        if (existing) {
            if (safeProps.taskId !== undefined)
                existing.taskId = Number(safeProps.taskId)
            if (safeProps.taskType !== undefined)
                existing.taskType = String(safeProps.taskType || "default")
            if (existing.minimized)
                existing.restoreFromDock()
            raiseWindow(key)
            return
        }
        const w = Math.min(Core.Theme.dp(620), Math.max(Core.Theme.dp(420), root.width - Core.Theme.dp(120)))
        const h = Math.min(Core.Theme.dp(460), Math.max(Core.Theme.dp(300), root.height - Core.Theme.dp(96)))
        const obj = inlineWindowComponent.createObject(root, {
            manager: root,
            pageKey: key,
            title: titleFor(key, title),
            pageSource: pageSourceFor(page),
            width: w,
            height: h,
            x: Math.max(Core.Theme.dp(18), (root.width - w) / 2 + Object.keys(windowsByKey).length * Core.Theme.dp(18)),
            y: Math.max(Core.Theme.dp(18), (root.height - h) / 2 + Object.keys(windowsByKey).length * Core.Theme.dp(18)),
            z: ++zCounter
        })
        if (!obj)
            return
        if (safeProps.taskId !== undefined)
            obj.taskId = Number(safeProps.taskId)
        if (safeProps.taskType !== undefined)
            obj.taskType = String(safeProps.taskType || "default")
        obj.closeRequested.connect(closePage)
        obj.minimizeRequested.connect(minimizePage)
        obj.restoreRequested.connect(restorePage)
        obj.raiseRequested.connect(raiseWindow)
        windowsByKey[key] = obj
        windowsByKey = windowsByKey
        refreshWindowCount()
        obj.clampGeometry()
    }

    function closePage(pageKey) {
        const key = String(pageKey || "")
        const obj = windowsByKey[key]
        if (!obj)
            return
        if (typeof App !== "undefined" && App && App.logMemorySample)
            App.logMemorySample("inline_child_close_before")
        if (Core.InlineWindowBus.activeInlineKey === key)
            Core.InlineWindowBus.setActiveInline("")
        if (obj.releaseContent)
            obj.releaseContent()
        delete windowsByKey[key]
        windowsByKey = windowsByKey
        refreshWindowCount()
        obj.destroy()
        layoutMinimized()
        trimMemoryDelay.restart()
        if (typeof App !== "undefined" && App && App.logMemorySample)
            Qt.callLater(function() { App.logMemorySample("inline_child_close_after_destroy") })
    }

    function restorePage(pageKey) {
        const obj = windowsByKey[String(pageKey || "")]
        if (!obj)
            return
        if (trimMemoryDelay.running)
            trimMemoryDelay.restart()
        obj.restoreFromDock()
        layoutMinimized()
    }

    function minimizePage(pageKey) {
        const obj = windowsByKey[String(pageKey || "")]
        if (!obj)
            return
        if (trimMemoryDelay.running)
            trimMemoryDelay.restart()
        obj.prepareMinimize()
        layoutMinimized()
    }

    function raiseWindow(pageKey) {
        const obj = windowsByKey[String(pageKey || "")]
        if (obj) {
            if (trimMemoryDelay.running)
                trimMemoryDelay.restart()
            obj.z = ++zCounter
            Core.InlineWindowBus.setActiveInline(String(pageKey || ""))
        }
    }

    function layoutMinimized() {
        var index = 0
        const keys = Object.keys(windowsByKey)
        const usableWidth = Math.max(dockWidth, root.width - dockGap * 2)
        const perRow = Math.max(1, Math.floor((usableWidth + dockGap) / (dockWidth + dockGap)))
        for (var i = 0; i < keys.length; ++i) {
            const obj = windowsByKey[keys[i]]
            if (!obj || !obj.minimized)
                continue
            const row = Math.floor(index / perRow)
            const col = index % perRow
            const dx = dockGap + col * (dockWidth + dockGap)
            const dy = root.height - dockGap - dockHeight - Core.Theme.dp(26) - row * (dockHeight + dockGap + Core.Theme.dp(8))
            obj.minimizeTo(dx, dy, dockWidth, dockHeight)
            obj.z = ++zCounter
            index += 1
        }
    }

    function minimizeVisiblePage(pageKey) {
        const obj = windowsByKey[String(pageKey || "")]
        if (!obj)
            return
        obj.prepareMinimize()
        layoutMinimized()
    }

    Component {
        id: inlineWindowComponent
        InlineChildWindow {}
    }

    Loader {
        id: nativeInputRouterLoader
        anchors.fill: parent
        active: true
        sourceComponent: NativeInlineInputRouterItem {
            managerItem: root
            visible: root.visible
        }
    }

    Timer {
        id: trimMemoryDelay
        interval: 900
        repeat: false
        onTriggered: {
            if (typeof App !== "undefined" && App && App.trimMemory)
                App.trimMemory()
        }
    }

    MouseArea {
        id: managerMoveArea
        z: 100002
        anchors.fill: parent
        enabled: false
        visible: false
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        propagateComposedEvents: false
        hoverEnabled: true
        onPressed: function(mouse) {
            const hit = root.resizeHit(mouse.x, mouse.y)
            if (hit.window && root.beginTopLevelResize(hit.window, hit.mode, mouse.x, mouse.y)) {
                cursorShape = root.cursorForResizeMode(hit.mode)
                root.resizePressConsumed = true
                mouse.accepted = true
                return
            }
            root.resizePressConsumed = false
            mouse.accepted = false
        }
        onPositionChanged: function(mouse) {
            if (root.activeResizeWindow) {
                root.updateTopLevelResize(mouse.x, mouse.y)
                mouse.accepted = true
            } else {
                const hit = root.resizeHit(mouse.x, mouse.y)
                cursorShape = root.cursorForResizeMode(hit.mode)
                mouse.accepted = false
            }
        }
        onReleased: function(mouse) {
            if (root.activeResizeWindow) {
                root.updateTopLevelResize(mouse.x, mouse.y)
                root.endTopLevelResize()
                mouse.accepted = true
            } else {
                mouse.accepted = false
            }
        }
        onClicked: function(mouse) {
            if (root.resizePressConsumed) {
                root.resizePressConsumed = false
                mouse.accepted = true
            } else {
                mouse.accepted = false
            }
        }
        onCanceled: {
            root.resizePressConsumed = false
            root.endTopLevelResize()
        }
    }

    Loader {
        id: nativeMoveLoader
        z: 100001
        anchors.fill: parent
        active: true
        source: active ? "../window/NativeInlineMoveArea.qml" : ""
        onStatusChanged: {
            if (status === Loader.Ready) {
                root.nativeInlineMoveFailed = false
                if (typeof App !== "undefined" && App && App.logRuntime)
                    App.logRuntime("inline manager native drag ready")
            } else if (status === Loader.Error) {
                root.nativeInlineMoveFailed = true
                console.warn("Native inline drag area unavailable, using QML fallback")
            }
        }
    }

    Connections {
        target: nativeMoveLoader.item
        function onTargetClicked(pageKey) {
            const obj = root.windowsByKey[String(pageKey || "")]
            if (obj && obj.minimized)
                root.restorePage(pageKey)
        }
    }

    onWidthChanged: {
        const keys = Object.keys(windowsByKey)
        for (var i = 0; i < keys.length; ++i) {
            if (windowsByKey[keys[i]] && !windowsByKey[keys[i]].minimized)
                windowsByKey[keys[i]].clampGeometry()
        }
        layoutMinimized()
    }
    onHeightChanged: {
        const keys = Object.keys(windowsByKey)
        for (var i = 0; i < keys.length; ++i) {
            if (windowsByKey[keys[i]] && !windowsByKey[keys[i]].minimized)
                windowsByKey[keys[i]].clampGeometry()
        }
        layoutMinimized()
    }
}
