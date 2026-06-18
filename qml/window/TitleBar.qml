import QtQuick
import QtQuick.Window
import QtQuick.Controls
import "../core" as Core
import "../controls"

Item {
    id: root

    readonly property real devicePixelRatio: Math.max(1.0, (root.Window.window && root.Window.window.screen) ? root.Window.window.screen.devicePixelRatio : Screen.devicePixelRatio)
    readonly property real physicalPixel: 1.0 / devicePixelRatio
    function snapToPhysicalPixel(value) {
        return Math.round(value / physicalPixel) * physicalPixel
    }

    property var leftMenus: []
    property bool navHidden: false
    property string windowTitle: ""
    property int frameRadius: Core.Theme.radius.window
    property bool alwaysOnTop: false
    property bool windowMaximized: false
    property bool showNavToggle: true
    property bool showColorButton: Core.Theme.showColorButton
    property bool showThemeButton: true
    property bool showPinButton: true
    property bool showWindowControls: true
    property bool useNativeCaption: false
    property bool systemMoveOnPress: false
    property var popupHost: null
    // Title bar spacing knobs: adjust these for the whole title-bar layout.
    // Lower titleButtonHeightRatio leaves more vertical gap around title buttons.
    property real titleButtonHeightRatio: 0.8
    property int rightButtonSize: Math.max(Core.Theme.dp(20), Math.round(height * titleButtonHeightRatio))
    property int titleOuterLeftMargin: Core.Theme.dp(7)
    property int titleOuterRightMargin: Core.Theme.dp(5)
    property int titleButtonSpacing: Core.Theme.dp(1)
    property int titleButtonSeparatorGap: Core.Theme.dp(12)
    property int titleTextLeftPadding: showNavToggle ? Core.Theme.dp(8) : Core.Theme.dp(7)
    property real nativeTitleBarHeight: height
    property real nativeCaptionLeftA: leftArea.x + titleDragBox.x
    property real nativeCaptionRightA: nativeCaptionLeftA + titleDragBox.width
    property real nativeCaptionLeftB: dragArea.x
    property real nativeCaptionRightB: dragArea.x + dragArea.width
    property var navToggleButtonItem: navToggleButtonLoader.item
    property alias titleDragItem: titleDragBox
    property alias leftMenusAreaItem: leftMenusArea
    property alias dragAreaItem: dragArea
    property var paletteButtonItem: paletteButtonLoader.item
    property var themeButtonItem: themeButtonLoader.item
    property var pinButtonItem: pinButtonLoader.item
    property double colorPopupClosedAt: 0
    property alias minimizeButtonItem: minimizeButton
    property alias maximizeButtonItem: maximizeButton
    property alias closeButtonItem: closeButton
    property bool minimizeButtonNativeHovered: false
    property bool maximizeButtonNativeHovered: false
    property bool closeButtonNativeHovered: false
    property alias rightAreaItem: rightArea

    property bool _dragStarted: false
    property bool _systemMoveAccepted: false
    property real _pressX: 0
    property real _pressY: 0
    property var _pressItem: null
    property double _lastPressAt: 0
    property bool _lastPressWasClick: false

    signal activateRequested()
    signal moveRequested(real localX, real localY)
    signal moveUpdated()
    signal moveFinished()
    signal minimizeRequested()
    signal toggleMaximizeRequested()
    signal closeRequested()
    signal themeToggleRequested(point localPos, string nextMode)
    signal themeTogglePrepared()
    signal alwaysOnTopRequested(bool enabled)
    signal toggleNavRequested()
    signal menuActionRequested(string action, string kind)
    signal menuActionPrepared(string action, string kind)

    function beginDrag(item, mx, my) {
        const p = item.mapToItem(root, mx, my)
        root.moveRequested(p.x, p.y)
    }

    function closeMenus() {
        if (menuPopupLoader.item)
            menuPopupLoader.item.close()
        if (colorPopupLoader.item)
            colorPopupLoader.item.close()
        if (paletteContextMenuLoader.item)
            paletteContextMenuLoader.item.close()
    }

    function smokeOpenFirstMenu() {
        if (!leftMenusArea || leftMenusArea.children.length <= 0 || root.leftMenus.length <= 0)
            return false
        const menuButton = leftMenusArea.children[0]
        if (!menuButton)
            return false
        if (colorPopupLoader.item)
            colorPopupLoader.item.close()
        menuPopupLoader.active = true
        Qt.callLater(function() {
            if (menuPopupLoader.item)
                menuPopupLoader.item.openFor(root.leftMenus[0].action, menuButton)
            if (typeof App !== "undefined" && App && App.logMemorySample)
                App.logMemorySample("title_menu_opened")
        })
        return true
    }

    function smokeOpenPalette() {
        const paletteButton = paletteButtonLoader.item
        if (!paletteButton)
            return false
        if (menuPopupLoader.item)
            menuPopupLoader.item.close()
        colorPopupLoader.active = true
        Qt.callLater(function() {
            if (colorPopupLoader.item)
                colorPopupLoader.item.openNear(paletteButton)
            if (typeof App !== "undefined" && App && App.logMemorySample)
                App.logMemorySample("palette_opened")
        })
        return true
    }

    function smokePopupState() {
        return "menu=" + (!!(menuPopupLoader.item && menuPopupLoader.item.visible))
               + ",palette=" + (!!(colorPopupLoader.item && colorPopupLoader.item.visible))
               + ",context=" + (!!(paletteContextMenuLoader.item && paletteContextMenuLoader.item.visible))
    }

    function dragPress(item, mx, my) {
        closeMenus()
        root.activateRequested()
        _pressItem = item
        _pressX = mx
        _pressY = my
        _dragStarted = false
        _systemMoveAccepted = false
        const now = Date.now()
        const possibleDoubleClick = _lastPressWasClick && now - _lastPressAt < 320
        _lastPressAt = now
        _lastPressWasClick = false
    }

    function dragMove(item, mx, my) {
        if (_pressItem !== item)
            return
        const moved = Math.abs(mx - _pressX) + Math.abs(my - _pressY)
        const dragThreshold = root.systemMoveOnPress && !root.useNativeCaption ? 1 : 5
        if (!_dragStarted && moved >= dragThreshold) {
            beginDrag(item, _pressX, _pressY)
            _dragStarted = true
        }
        if (_dragStarted)
            root.moveUpdated()
    }

    function dragRelease() {
        const wasDragStarted = _dragStarted
        if (_dragStarted && !root._systemMoveAccepted)
            root.moveFinished()
        _lastPressWasClick = !wasDragStarted && !root._systemMoveAccepted
        resetDragState()
    }

    function resetDragState() {
        clearPointerTracking()
        _systemMoveAccepted = false
    }

    function clearPointerTracking() {
        _dragStarted = false
        _pressItem = null
    }

    Rectangle {
        anchors.fill: parent
        radius: root.frameRadius
        color: Core.Theme.color.titleBar
        antialiasing: true
        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.max(0, parent.height - root.frameRadius)
        color: Core.Theme.color.titleBar
        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }

    BackgroundRipple {
        anchors.fill: parent
        z: 1
        radius: root.frameRadius
        startX: parent.width * 0.92
        startY: parent.height * 0.08
        delayMs: 0
        colorRole: "titleBar"
        opacityScale: 1.0
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        y: root.snapToPhysicalPixel(parent.height) - height
        z: 3
        height: root.physicalPixel
        color: Core.Theme.color.hairline
        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }
    Row {
        id: leftArea
        z: 2
        anchors.left: parent.left
        anchors.leftMargin: root.titleOuterLeftMargin
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: root.titleButtonSpacing

        Loader {
            id: navToggleButtonLoader
            active: root.showNavToggle
            width: active ? Core.Theme.dp(26) : 0
            height: active ? width : 0
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: IconButton {
                width: navToggleButtonLoader.width
                height: navToggleButtonLoader.height
                iconName: root.navHidden ? "chevron-right" : "chevron-left"
                strokeWidth: 0.90
                noBorder: true
                tooltip: root.navHidden ? "展开导航" : "隐藏导航"
                clickOnPress: true
                onClicked: root.toggleNavRequested()
            }
        }

        Item {
            id: titleDragBox
            width: Math.min(Core.Theme.dp(260), Math.max(Core.Theme.dp(24), titleText.implicitWidth + root.titleTextLeftPadding + Core.Theme.dp(10)))
            height: parent.height

            Text {
                id: titleText
                anchors.left: parent.left
                anchors.leftMargin: root.titleTextLeftPadding
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                verticalAlignment: Text.AlignVCenter
                text: root.windowTitle.length > 0 ? root.windowTitle : Core.AppInfo.windowTitle
                color: Core.Theme.color.text
                font.pixelSize: Core.Theme.fontSize.caption
                font.family: Core.Theme.appFontFamily
                font.bold: false
                font.weight: Font.Light
                elide: Text.ElideRight
            }

            MouseArea {
                anchors.fill: parent
                enabled: !root.useNativeCaption
                acceptedButtons: Qt.LeftButton
                onPressed: function(mouse) { root.dragPress(titleDragBox, mouse.x, mouse.y) }
                onPositionChanged: function(mouse) { if (pressed) root.dragMove(titleDragBox, mouse.x, mouse.y) }
                onReleased: root.dragRelease()
                onCanceled: root.dragRelease()
                onDoubleClicked: { root.dragRelease(); root.toggleMaximizeRequested() }
            }
        }

        Row {
            id: leftMenusArea
            height: parent.height
            spacing: root.titleButtonSpacing

            Repeater {
                model: root.leftMenus
                delegate: AppButton {
                    height: Core.Theme.dp(24)
                    anchors.verticalCenter: parent.verticalCenter
                    paddingH: Core.Theme.dp(7)
                    minButtonWidth: Core.Theme.dp(34)
                    radius: Core.Theme.radius.button
                    labelPixelSize: Core.Theme.fontSize.caption
                    text: modelData.text
                    clickOnPress: true
                    onClicked: {
                        if (colorPopupLoader.item)
                            colorPopupLoader.item.close()
                        const menuButton = this
                        menuPopupLoader.active = true
                        Qt.callLater(function() {
                            if (menuPopupLoader.item)
                                menuPopupLoader.item.openFor(modelData.action, menuButton)
                            if (typeof App !== "undefined" && App && App.logMemorySample)
                                App.logMemorySample("title_menu_opened")
                        })
                    }
                }
            }
        }
    }

    MouseArea {
        id: dragArea
        z: 2
        anchors.left: leftArea.right
        anchors.right: rightArea.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        enabled: !root.useNativeCaption
        acceptedButtons: Qt.LeftButton
        preventStealing: false
        hoverEnabled: false

        onPressed: function(mouse) { root.dragPress(dragArea, mouse.x, mouse.y) }
        onPositionChanged: function(mouse) { if (pressed) root.dragMove(dragArea, mouse.x, mouse.y) }
        onReleased: root.dragRelease()
        onCanceled: root.dragRelease()
        onDoubleClicked: { root.dragRelease(); root.toggleMaximizeRequested() }
    }

    Row {
        id: rightArea
        z: 2
        anchors.right: parent.right
        anchors.rightMargin: root.titleOuterRightMargin
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: root.titleButtonSpacing

        Loader {
            id: paletteButtonLoader
            active: root.showColorButton
            width: active ? root.rightButtonSize : 0
            height: active ? root.rightButtonSize : 0
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: IconButton {
                id: paletteButton
                width: paletteButtonLoader.width
                height: paletteButtonLoader.height
                iconName: "palette"
                strokeWidth: 0.90
                noBorder: true
                tooltip: "主题色"
                clickOnPress: true
                onClicked: {
                    if (colorPopupLoader.item && colorPopupLoader.item.visible) {
                        colorPopupLoader.item.close()
                    } else {
                        if (Date.now() - root.colorPopupClosedAt < 220)
                            return
                        if (menuPopupLoader.item)
                            menuPopupLoader.item.close()
                        colorPopupLoader.active = true
                        Qt.callLater(function() {
                            if (colorPopupLoader.item)
                                colorPopupLoader.item.openNear(paletteButton)
                            if (typeof App !== "undefined" && App && App.logMemorySample)
                                App.logMemorySample("palette_opened")
                        })
                    }
                }
                onRightClicked: function(localX, localY) {
                    const paletteButtonItem = paletteButton
                    const clickX = localX
                    const clickY = localY
                    paletteContextMenuLoader.active = true
                    Qt.callLater(function() {
                        if (!paletteContextMenuLoader.item)
                            return
                        const host = paletteContextMenuLoader.item.parent
                        const p = paletteButtonItem.mapToItem(host, clickX, clickY)
                        paletteContextMenuLoader.item.openForActions([
                            { "text": "隐藏调色按钮", "action": "hidePalette", "available": true }
                        ], p.x, p.y)
                    })
                }
            }
        }

        Loader {
            id: themeButtonLoader
            active: root.showThemeButton
            width: active ? root.rightButtonSize : 0
            height: active ? root.rightButtonSize : 0
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: IconButton {
                id: themeButton
                width: themeButtonLoader.width
                height: themeButtonLoader.height
                iconName: Core.Theme.mode === "dark" ? "sun" : "moon"
                strokeWidth: 0.90
                noBorder: true
                tooltip: "日夜切换"
                onIntent: root.themeTogglePrepared()
                onClicked: {
                    const next = Core.Theme.mode === "dark" ? "light" : "dark"
                    const p = themeButton.mapToItem(root, themeButton.width / 2, themeButton.height / 2)
                    root.themeToggleRequested(Qt.point(p.x, p.y), next)
                }
            }
        }

        Loader {
            id: pinButtonLoader
            active: root.showPinButton
            width: active ? root.rightButtonSize : 0
            height: active ? root.rightButtonSize : 0
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: IconButton {
                width: pinButtonLoader.width
                height: pinButtonLoader.height
                accent: false
                noBorder: true
                strokeWidth: root.alwaysOnTop ? 1.0 : 0.90
                iconName: root.alwaysOnTop ? "pin-filled" : "pin"
                iconColor: root.alwaysOnTop ? (Core.Theme.mode === "dark" ? Core.Theme.white : "#20242C") : Core.Theme.color.icon
                tooltip: root.alwaysOnTop ? "取消置顶" : "窗口置顶"
                clickOnPress: true
                onClicked: root.alwaysOnTopRequested(!root.alwaysOnTop)
            }
        }

        Item {
            visible: paletteButtonLoader.active || themeButtonLoader.active || pinButtonLoader.active
            width: visible ? root.titleButtonSeparatorGap : 0
            height: parent.height

            Rectangle {
                width: 1
                height: root.rightButtonSize
                anchors.centerIn: parent
                color: Core.Theme.color.hairline
                opacity: 0.72
                Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            }
        }

        IconButton { id: minimizeButton; visible: root.showWindowControls; width: visible ? root.rightButtonSize : 0; height: visible ? root.rightButtonSize : 0; anchors.verticalCenter: parent.verticalCenter; iconName: "minimize"; strokeWidth: 0.90; noBorder: true; forceHovered: root.minimizeButtonNativeHovered; onClicked: root.minimizeRequested() }
        IconButton { id: maximizeButton; visible: root.showWindowControls; width: visible ? root.rightButtonSize : 0; height: visible ? root.rightButtonSize : 0; anchors.verticalCenter: parent.verticalCenter; iconName: root.windowMaximized ? "restore" : "maximize"; strokeWidth: 0.90; noBorder: true; forceHovered: root.maximizeButtonNativeHovered; onClicked: root.toggleMaximizeRequested() }
        IconButton { id: closeButton; visible: root.showWindowControls; width: visible ? root.rightButtonSize : 0; height: visible ? root.rightButtonSize : 0; anchors.verticalCenter: parent.verticalCenter; iconName: "close"; strokeWidth: 0.90; noBorder: true; forceHovered: root.closeButtonNativeHovered; onClicked: root.closeRequested() }
    }

    Loader {
        id: paletteContextMenuLoader
        active: false
        sourceComponent: AppContextMenu {
            parent: root.popupHost ? root.popupHost : (root.Window.window ? root.Window.window.contentItem : root)
            menuWidth: Core.Theme.dp(188)
            onActionTriggered: function(action) {
                if (action === "hidePalette") {
                    if (colorPopupLoader.item)
                        colorPopupLoader.item.close()
                    if (typeof App !== "undefined" && App && App.theme)
                        App.theme.setShowColorButton(false)
                    else if (typeof App !== "undefined" && App && App.settings)
                        App.settings.setValue("ui/showColorButton", false)
                }
            }
            onVisibleChanged: {
                if (!visible)
                    Qt.callLater(function() { paletteContextMenuLoader.active = false })
            }
        }
    }

    Loader {
        id: menuPopupLoader
        active: false
        sourceComponent: AppMenu {
            parent: root.popupHost ? root.popupHost : (root.Window.window ? root.Window.window.contentItem : root)
            onActionPrepared: function(action, kind) { root.menuActionPrepared(action, kind) }
            onActionTriggered: function(action, kind) { root.menuActionRequested(action, kind) }
            onClosed: Qt.callLater(function() { menuPopupLoader.active = false })
        }
    }

    Loader {
        id: colorPopupLoader
        active: false
        sourceComponent: ColorPalettePopup {
            parent: root.popupHost ? root.popupHost : (root.Window.window ? root.Window.window.contentItem : root)
            onClosed: {
                root.colorPopupClosedAt = Date.now()
                colorPopupLoader.active = false
            }
        }
    }
}


