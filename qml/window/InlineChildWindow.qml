import QtQuick
import "../core" as Core
import "../controls"

Item {
    id: root

    property var manager: null
    property string pageKey: ""
    property int taskId: -1
    property string taskType: "default"
    property string title: "Child"
    property string pageSource: ""
    property bool minimized: false
    property real minWindowWidth: Core.Theme.dp(360)
    property real minWindowHeight: Core.Theme.dp(260)
    property real dockWidth: Core.Theme.dp(190)
    property real dockHeight: Core.Theme.dp(36)
    property real savedX: 0
    property real savedY: 0
    property real savedWidth: 0
    property real savedHeight: 0
    property real pressX: 0
    property real pressY: 0
    property real startX: 0
    property real startY: 0
    property real startWidth: 0
    property real startHeight: 0
    property string resizeMode: ""
    property bool moving: false
    property bool minimizedDragging: false
    property bool closePending: false
    property bool contentActive: true
    property real minimizedPressX: 0
    property real minimizedPressY: 0
    property real minimizedStartX: 0
    property real minimizedStartY: 0
    property bool inlineChildWindow: true
    property bool inlineHoverActive: false
    property color brightEdgeColor: Core.Theme.mode === "dark" ? Core.Theme.alpha(Qt.lighter(Core.Theme.primary, 1.65), 0.88) : Core.Theme.color.outlineAccent
    property real moveAnchorX: 0
    property real moveAnchorY: 0
    property bool nativeTitleDragReady: manager && manager.nativeInlineMoveAvailable

    signal closeRequested(string pageKey)
    signal minimizeRequested(string pageKey)
    signal restoreRequested(string pageKey)
    signal raiseRequested(string pageKey)

    width: Core.Theme.dp(640)
    height: Core.Theme.dp(440)
    visible: true

    function applyTaskPropsToContent() {
        const item = contentLoader.item
        if (item && item.taskId !== undefined)
            item.taskId = root.taskId
        if (item && item.taskType !== undefined)
            item.taskType = root.taskType
    }

    onTaskIdChanged: applyTaskPropsToContent()
    onTaskTypeChanged: applyTaskPropsToContent()

    function clampGeometry() {
        if (!parent)
            return
        const maxW = Math.max(minWindowWidth, parent.width - Core.Theme.dp(12))
        const maxH = Math.max(minWindowHeight, parent.height - Core.Theme.dp(12))
        width = Math.max(minWindowWidth, Math.min(width, maxW))
        height = Math.max(minWindowHeight, Math.min(height, maxH))
        x = Math.max(Core.Theme.dp(6), Math.min(x, parent.width - width - Core.Theme.dp(6)))
        y = Math.max(Core.Theme.dp(6), Math.min(y, parent.height - height - Core.Theme.dp(6)))
    }

    function clampPositionOnly() {
        if (!parent)
            return
        x = Math.max(Core.Theme.dp(6), Math.min(x, parent.width - width - Core.Theme.dp(6)))
        y = Math.max(Core.Theme.dp(6), Math.min(y, parent.height - height - Core.Theme.dp(6)))
    }

    function requestGrowthForRect(nx, ny, nw, nh) {
        // Inline windows no longer expand the native main window.
    }

    function pointerInManager(item, mx, my) {
        if (!parent || !item)
            return Qt.point(mx, my)
        return item.mapToItem(parent, mx, my)
    }

    function isTopEventTarget(item, mx, my) {
        if (!manager || !manager.isTopWindowAt || !parent || !item)
            return true
        const p = pointerInManager(item, mx, my)
        return manager.isTopWindowAt(root, p.x, p.y, true)
    }

    function beginMoveFromItem(item, mx, my) {
        if (minimized || !parent || !item)
            return
        const p = item.mapToItem(parent, mx, my)
        raiseRequested(pageKey)
        moving = true
        moveAnchorX = p.x - x
        moveAnchorY = p.y - y
        startX = x
        startY = y
    }

    function updateMoveFromItem(item, mx, my) {
        if (minimized || !moving || !parent || !item)
            return
        const p = item.mapToItem(parent, mx, my)
        x = p.x - moveAnchorX
        y = p.y - moveAnchorY
    }

    function requestDragBoundaryGrowth(item, mx, my) {
        // Kept as a compatibility no-op.
    }

    function endMove() {
        moving = false
        if (parent && parent.endWorkspaceGrowth)
            parent.endWorkspaceGrowth()
    }

    function beginResize(mode, item, mx, my) {
        if (minimized)
            return
        const p = pointerInManager(item, mx, my)
        raiseRequested(pageKey)
        moving = false
        resizeMode = mode
        pressX = p.x
        pressY = p.y
        startX = x
        startY = y
        startWidth = width
        startHeight = height
    }

    function updateResize(item, mx, my) {
        if (resizeMode.length === 0 || minimized)
            return
        const p = pointerInManager(item, mx, my)
        const dx = p.x - pressX
        const dy = p.y - pressY
        var nx = startX
        var ny = startY
        var nw = startWidth
        var nh = startHeight
        if (resizeMode.indexOf("right") >= 0)
            nw = startWidth + dx
        if (resizeMode.indexOf("bottom") >= 0)
            nh = startHeight + dy
        if (resizeMode.indexOf("left") >= 0) {
            nw = startWidth - dx
            nx = startX + dx
        }
        if (resizeMode.indexOf("top") >= 0) {
            nh = startHeight - dy
            ny = startY + dy
        }
        if (nw < minWindowWidth) {
            if (resizeMode.indexOf("left") >= 0)
                nx = startX + startWidth - minWindowWidth
            nw = minWindowWidth
        }
        if (nh < minWindowHeight) {
            if (resizeMode.indexOf("top") >= 0)
                ny = startY + startHeight - minWindowHeight
            nh = minWindowHeight
        }
        if (parent) {
            requestGrowthForRect(nx, ny, nw, nh)
            if (nx < Core.Theme.dp(6)) {
                nw -= Core.Theme.dp(6) - nx
                nx = Core.Theme.dp(6)
            }
            if (ny < Core.Theme.dp(6)) {
                nh -= Core.Theme.dp(6) - ny
                ny = Core.Theme.dp(6)
            }
            nw = Math.min(nw, parent.width - nx - Core.Theme.dp(6))
            nh = Math.min(nh, parent.height - ny - Core.Theme.dp(6))
        }
        x = nx
        y = ny
        width = Math.max(minWindowWidth, nw)
        height = Math.max(minWindowHeight, nh)
    }

    function endResize() {
        resizeMode = ""
        if (parent && parent.endWorkspaceGrowth)
            parent.endWorkspaceGrowth()
    }

    function beginMinimizedPointer(item, mx, my) {
        const p = pointerInManager(item, mx, my)
        raiseRequested(pageKey)
        minimizedDragging = false
        minimizedPressX = p.x
        minimizedPressY = p.y
        minimizedStartX = x
        minimizedStartY = y
    }

    function updateMinimizedPointer(item, mx, my) {
        if (!minimized)
            return
        const p = pointerInManager(item, mx, my)
        const dx = p.x - minimizedPressX
        const dy = p.y - minimizedPressY
        if (!minimizedDragging && Math.abs(dx) + Math.abs(dy) < Core.Theme.dp(5))
            return
        minimizedDragging = true
        x = minimizedStartX + dx
        y = minimizedStartY + dy
        clampPositionOnly()
    }

    function endMinimizedPointer() {
        if (!minimized)
            return
        if (!minimizedDragging)
            restoreRequested(pageKey)
        minimizedDragging = false
    }

    function prepareMinimize() {
        if (!minimized) {
            savedX = x
            savedY = y
            savedWidth = width
            savedHeight = height
        }
        minimized = true
        if (Qt.platform.os === "linux" && Core.Theme.lowMemoryMode)
            contentActive = false
    }

    function minimizeTo(dx, dy, dw, dh) {
        if (!minimized)
            prepareMinimize()
        x = dx
        y = dy
        width = dw
        height = dh
    }

    function restoreFromDock() {
        minimized = false
        x = savedX
        y = savedY
        width = Math.max(minWindowWidth, savedWidth)
        height = Math.max(minWindowHeight, savedHeight)
        clampGeometry()
        raiseRequested(pageKey)
        contentActive = true
    }

    function requestCloseNow() {
        root.setInlineHover(false)
        closePending = true
        visible = false
        closeRequested(pageKey)
    }

    function releaseContent() {
        contentActive = false
        contentLoader.source = ""
        contentLoader.active = false
    }

    function setInlineHover(active) {
        if (inlineHoverActive === active)
            return
        inlineHoverActive = active
        Core.InlineWindowBus.setInlineHover(pageKey, active)
    }

    Component.onDestruction: {
        if (inlineHoverActive)
            Core.InlineWindowBus.setInlineHover(pageKey, false)
    }

    HoverHandler {
        id: inlineHoverHandler
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onHoveredChanged: root.setInlineHover(hovered)
    }

    Repeater {
        model: [
            { m: Core.Theme.dp(20), y: Core.Theme.dp(10), a: Core.Theme.mode === "dark" ? 0.035 : 0.020, ma: Core.Theme.mode === "dark" ? 0.070 : 0.045 },
            { m: Core.Theme.dp(16), y: Core.Theme.dp(8), a: Core.Theme.mode === "dark" ? 0.050 : 0.030, ma: Core.Theme.mode === "dark" ? 0.095 : 0.060 },
            { m: Core.Theme.dp(12), y: Core.Theme.dp(6), a: Core.Theme.mode === "dark" ? 0.070 : 0.042, ma: Core.Theme.mode === "dark" ? 0.125 : 0.080 },
            { m: Core.Theme.dp(8), y: Core.Theme.dp(4), a: Core.Theme.mode === "dark" ? 0.090 : 0.055, ma: Core.Theme.mode === "dark" ? 0.155 : 0.100 },
            { m: Core.Theme.dp(4), y: Core.Theme.dp(2), a: Core.Theme.mode === "dark" ? 0.105 : 0.070, ma: Core.Theme.mode === "dark" ? 0.180 : 0.118 }
        ]
        delegate: Rectangle {
            property real spread: modelData.m * (root.minimized ? 0.50 : 0.67)
            x: -spread
            y: -spread + modelData.y * (root.minimized ? 0.35 : 0.75)
            width: parent.width + spread * 2
            height: parent.height + spread * 2
            radius: Core.Theme.radius.window + spread
        color: Core.Theme.color.shadow
        opacity: root.minimized ? modelData.ma : modelData.a
        z: index
        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
        Behavior on opacity { NumberAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }
    }

    Rectangle {
        id: shell
        z: 10
        anchors.fill: parent
        radius: Core.Theme.radius.window
        color: Core.Theme.color.surface
        border.color: "transparent"
        border.width: 1
        antialiasing: true
        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }

    Rectangle {
        z: 11
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: minimized ? parent.height : Core.Theme.metrics.titleBarHeight
        radius: shell.radius
        color: Core.Theme.color.titleBar
        antialiasing: true
        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }

    Rectangle {
        z: 12
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Core.Theme.metrics.titleBarHeight - 1
        height: 1
        visible: !minimized
        color: Core.Theme.color.hairline
        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }

    Row {
        id: titleRow
        z: 1200
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: minimized ? parent.height : Core.Theme.metrics.titleBarHeight
        anchors.leftMargin: Core.Theme.dp(10)
        anchors.rightMargin: Core.Theme.dp(3)
        spacing: Core.Theme.dp(4)

        Text {
            width: parent.width - controlsHost.width - Core.Theme.dp(8)
            height: parent.height
            text: root.title
            color: Core.Theme.color.text
            font.pixelSize: Core.Theme.fontSize.caption
            font.family: Core.Theme.appFontFamily
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        Item {
            id: controlsHost
            width: root.minimized ? 0 : controlsOverlay.width
            height: parent.height
            visible: !root.minimized
        }
    }

    Row {
        id: controlsOverlay
        z: 2000
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Math.round((Core.Theme.metrics.titleBarHeight - height) / 2)
        anchors.rightMargin: Core.Theme.dp(3)
        height: Math.round(Core.Theme.metrics.titleBarHeight * 0.82)
        spacing: Core.Theme.dp(2)
        visible: !root.minimized

        IconButton {
            width: controlsOverlay.height
            height: controlsOverlay.height
            iconName: "minimize"
            noBorder: true
            onClicked: root.minimizeRequested(root.pageKey)
        }

        IconButton {
            width: controlsOverlay.height
            height: controlsOverlay.height
            iconName: "close"
            noBorder: true
            onClicked: root.requestCloseNow()
        }
    }

    MouseArea {
        id: titleBarEventShield
        z: 20
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: minimized ? parent.height : Core.Theme.metrics.titleBarHeight
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        preventStealing: true
        propagateComposedEvents: false
        onWheel: function(wheel) { wheel.accepted = true }
        onPressed: function(mouse) {
            if (!root.isTopEventTarget(titleBarEventShield, mouse.x, mouse.y)) {
                mouse.accepted = true
                return
            }
            root.raiseRequested(root.pageKey)
            Core.InlineWindowBus.setActiveInline(root.pageKey)
            mouse.accepted = true
        }
        onReleased: function(mouse) { mouse.accepted = true }
        onClicked: function(mouse) { mouse.accepted = true }
    }

    Rectangle {
        z: 29
        anchors.fill: parent
        radius: shell.radius
        color: "transparent"
        border.color: root.brightEdgeColor
        border.width: 1
        antialiasing: true
        Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }

    MouseArea {
        id: titleMouseArea
        z: 21
        enabled: !root.nativeTitleDragReady && root.visible
        visible: enabled
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: root.minimized ? 0 : controlsHost.width + Core.Theme.dp(12)
        anchors.top: parent.top
        height: minimized ? parent.height : Core.Theme.metrics.titleBarHeight
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        propagateComposedEvents: false
        onWheel: function(wheel) {
            wheel.accepted = true
        }
        onPressed: function(mouse) {
            if (!root.isTopEventTarget(titleMouseArea, mouse.x, mouse.y)) {
                mouse.accepted = true
                return
            }
            root.raiseRequested(root.pageKey)
            Core.InlineWindowBus.setActiveInline(root.pageKey)
            root.beginMoveFromItem(titleMouseArea, mouse.x, mouse.y)
            mouse.accepted = true
        }
        onPositionChanged: function(mouse) {
            if (pressed)
                root.updateMoveFromItem(titleMouseArea, mouse.x, mouse.y)
            mouse.accepted = pressed
        }
        onReleased: function(mouse) {
            root.endMove()
            mouse.accepted = true
        }
        onCanceled: function() {
            root.moving = false
        }
        onDoubleClicked: function(mouse) {
            if (root.minimized) {
                root.restoreRequested(root.pageKey)
                mouse.accepted = true
            }
        }
    }

    MouseArea {
        id: blankEventBlocker
        z: 14
        anchors.fill: parent
        anchors.topMargin: root.minimized ? 0 : Core.Theme.metrics.titleBarHeight
        enabled: root.visible
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        preventStealing: true
        propagateComposedEvents: false
        onWheel: function(wheel) {
            wheel.accepted = true
        }
        onPressed: function(mouse) {
            if (!root.isTopEventTarget(blankEventBlocker, mouse.x, mouse.y)) {
                mouse.accepted = true
                return
            }
            root.raiseRequested(root.pageKey)
            Core.InlineWindowBus.setActiveInline(root.pageKey)
            mouse.accepted = true
        }
        onReleased: function(mouse) { mouse.accepted = true }
        onClicked: function(mouse) { mouse.accepted = true }
        onDoubleClicked: function(mouse) { mouse.accepted = true }
    }

    Loader {
        id: nativeTitleDragLoader
        z: 21
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: root.minimized ? 0 : controlsHost.width + Core.Theme.dp(12)
        anchors.top: parent.top
        height: root.minimized ? parent.height : Core.Theme.metrics.titleBarHeight
        active: !root.nativeTitleDragReady
        sourceComponent: nativeTitleDragComponent
        onStatusChanged: {
            if (status === Loader.Ready) {
                if (typeof App !== "undefined" && App && App.logRuntime)
                    App.logRuntime("inline native title drag ready")
            } else if (status === Loader.Error) {
                console.warn("Native inline title drag area unavailable")
            }
        }
    }

    Component {
        id: nativeTitleDragComponent
        NativeInlineMoveArea {
            targetItem: root
            onDragStarted: root.raiseRequested(root.pageKey)
            onClicked: {
                if (root.minimized)
                    root.restoreRequested(root.pageKey)
            }
        }
    }

    Loader {
        id: contentLoader
        z: 15
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 0
        anchors.topMargin: Core.Theme.metrics.titleBarHeight
        active: root.contentActive
        asynchronous: true
        source: root.pageSource
        visible: !root.minimized && active
        onLoaded: root.applyTaskPropsToContent()
    }

    MouseArea {
        id: nonPrimaryEventBlocker
        z: 96
        anchors.fill: parent
        anchors.leftMargin: Core.Theme.dp(18)
        anchors.rightMargin: Core.Theme.dp(18)
        anchors.topMargin: root.minimized ? Core.Theme.dp(18) : Core.Theme.metrics.titleBarHeight + Core.Theme.dp(4)
        anchors.bottomMargin: Core.Theme.dp(18)
        enabled: root.visible
        acceptedButtons: Qt.RightButton | Qt.MiddleButton
        preventStealing: true
        propagateComposedEvents: false
        onPressed: function(mouse) {
            if (!root.isTopEventTarget(nonPrimaryEventBlocker, mouse.x, mouse.y)) {
                mouse.accepted = true
                return
            }
            root.raiseRequested(root.pageKey)
            Core.InlineWindowBus.setActiveInline(root.pageKey)
            mouse.accepted = true
        }
        onReleased: function(mouse) { mouse.accepted = true }
        onClicked: function(mouse) { mouse.accepted = true }
    }

    component ResizeGrip: MouseArea {
        id: gripArea
        required property string gripMode
        required property int gripCursor
        z: 1000
        enabled: !root.minimized
        cursorShape: gripCursor
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        preventStealing: true
        propagateComposedEvents: false
        onWheel: function(wheel) {
            wheel.accepted = true
        }
        onPressed: function(mouse) {
            if (!root.isTopEventTarget(gripArea, mouse.x, mouse.y)) {
                mouse.accepted = true
                return
            }
            mouse.accepted = true
            root.beginResize(gripMode, gripArea, mouse.x, mouse.y)
        }
        onPositionChanged: function(mouse) {
            if (pressed) {
                mouse.accepted = true
                root.updateResize(gripArea, mouse.x, mouse.y)
            }
        }
        onReleased: root.endResize()
        onCanceled: root.endResize()
    }

    ResizeGrip { gripMode: "left-top"; gripCursor: Qt.SizeFDiagCursor; anchors.left: parent.left; anchors.top: parent.top; width: Core.Theme.dp(8); height: Core.Theme.dp(8) }
    ResizeGrip { gripMode: "right-top"; gripCursor: Qt.SizeBDiagCursor; anchors.right: parent.right; anchors.top: parent.top; width: Core.Theme.dp(8); height: Core.Theme.dp(8) }
    ResizeGrip { gripMode: "left-bottom"; gripCursor: Qt.SizeBDiagCursor; anchors.left: parent.left; anchors.bottom: parent.bottom; width: Core.Theme.dp(8); height: Core.Theme.dp(8) }
    ResizeGrip { gripMode: "right-bottom"; gripCursor: Qt.SizeFDiagCursor; anchors.right: parent.right; anchors.bottom: parent.bottom; width: Core.Theme.dp(8); height: Core.Theme.dp(8) }
    ResizeGrip { gripMode: "left"; gripCursor: Qt.SizeHorCursor; anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.topMargin: Core.Theme.dp(8); anchors.bottomMargin: Core.Theme.dp(8); width: Core.Theme.dp(4) }
    ResizeGrip { gripMode: "right"; gripCursor: Qt.SizeHorCursor; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.topMargin: Core.Theme.dp(8); anchors.bottomMargin: Core.Theme.dp(8); width: Core.Theme.dp(4) }
    ResizeGrip { gripMode: "top"; gripCursor: Qt.SizeVerCursor; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.leftMargin: Core.Theme.dp(8); anchors.rightMargin: Core.Theme.dp(8); height: Core.Theme.dp(4) }
    ResizeGrip { gripMode: "bottom"; gripCursor: Qt.SizeVerCursor; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.leftMargin: Core.Theme.dp(8); anchors.rightMargin: Core.Theme.dp(8); height: Core.Theme.dp(4) }
}
