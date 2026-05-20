import QtQuick
import QtQuick.Window
import QtQuick.Controls
import "../core" as Core
import "../controls"

Item {
    id: root

    property var leftMenus: []
    property bool navHidden: false
    property string windowTitle: ""
    property int frameRadius: Core.Theme.radius.window
    property bool alwaysOnTop: false
    property bool windowMaximized: false
    property bool showNavToggle: true
    property bool showColorButton: Core.Theme.showColorButton

    property bool _dragStarted: false
    property real _pressX: 0
    property real _pressY: 0
    property var _pressItem: null

    signal activateRequested()
    signal moveRequested(real localX, real localY)
    signal moveUpdated()
    signal moveFinished()
    signal minimizeRequested()
    signal toggleMaximizeRequested()
    signal closeRequested()
    signal themeToggleRequested(point localPos, string nextMode)
    signal alwaysOnTopRequested(bool enabled)
    signal toggleNavRequested()
    signal menuActionRequested(string action, string kind)

    function beginDrag(item, mx, my) {
        const p = item.mapToItem(root, mx, my)
        root.moveRequested(p.x, p.y)
    }

    function dragPress(item, mx, my) {
        root.activateRequested()
        _pressItem = item
        _pressX = mx
        _pressY = my
        _dragStarted = false
    }

    function dragMove(item, mx, my) {
        if (_pressItem !== item)
            return
        const moved = Math.abs(mx - _pressX) + Math.abs(my - _pressY)
        if (!_dragStarted && moved >= 5) {
            beginDrag(item, _pressX, _pressY)
            _dragStarted = true
        }
        if (_dragStarted)
            root.moveUpdated()
    }

    function dragRelease() {
        if (_dragStarted)
            root.moveFinished()
        _dragStarted = false
        _pressItem = null
    }

    Rectangle {
        anchors.fill: parent
        radius: root.frameRadius
        color: Core.Theme.color.titleBar
        antialiasing: true
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.max(0, parent.height - root.frameRadius)
        color: Core.Theme.color.titleBar
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Core.Theme.color.hairline
    }

    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: Core.Theme.dp(8)
        anchors.bottom: parent.bottom
        width: Core.Theme.dp(68)
        height: Math.max(1, Core.Theme.dp(2))
        radius: 1
        color: Core.Theme.primary
        opacity: 0.52
    }

    Row {
        id: leftArea
        z: 2
        anchors.left: parent.left
        anchors.leftMargin: Core.Theme.dp(7)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Core.Theme.dp(1)

        IconButton {
            id: navToggleButton
            visible: root.showNavToggle
            width: visible ? Core.Theme.dp(26) : 0
            height: Core.Theme.dp(24)
            iconName: root.navHidden ? "menu" : "drag"
            strokeWidth: 0.90
            noBorder: true
            tooltip: root.navHidden ? "展开导航栏" : "隐藏导航栏"
            onClicked: root.toggleNavRequested()
        }

        Item {
            id: titleDragBox
            width: Math.min(Core.Theme.dp(195), Math.max(Core.Theme.dp(112), titleText.implicitWidth + Core.Theme.dp(4)))
            height: Core.Theme.dp(26)

            Text {
                id: titleText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.windowTitle.length > 0 ? root.windowTitle : "QML 无边框框架"
                color: Core.Theme.color.text
                font.pixelSize: Core.Theme.fontSize.caption
                font.bold: false
                font.weight: Font.Light
                elide: Text.ElideRight
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onPressed: function(mouse) { root.dragPress(titleDragBox, mouse.x, mouse.y) }
                onPositionChanged: function(mouse) { if (pressed) root.dragMove(titleDragBox, mouse.x, mouse.y) }
                onReleased: root.dragRelease()
                onCanceled: root.dragRelease()
                onDoubleClicked: { root.dragRelease(); root.toggleMaximizeRequested() }
            }
        }

        Repeater {
            model: root.leftMenus
            delegate: AppButton {
                height: Core.Theme.dp(24)
                paddingH: Core.Theme.dp(7)
                minButtonWidth: Core.Theme.dp(34)
                radius: Core.Theme.radius.button
                labelPixelSize: Core.Theme.fontSize.caption
                text: modelData.text
                clickOnPress: true
                onClicked: { colorPopup.close(); menuPopup.openFor(modelData.action, this) }
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
        anchors.rightMargin: Core.Theme.dp(7)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Core.Theme.dp(1)

        IconButton {
            id: paletteButton
            visible: root.showColorButton
            width: visible ? Core.Theme.dp(28) : 0
            height: Core.Theme.dp(24)
            iconName: "palette"
            strokeWidth: 0.90
            noBorder: true
            tooltip: "主题色"
            clickOnPress: true
            onClicked: {
                if (colorPopup.visible) {
                    colorPopup.close()
                } else {
                    menuPopup.close()
                    colorPopup.openNear(paletteButton)
                }
            }
            onRightClicked: function(localX, localY) {
                const host = paletteContextMenu.parent
                const p = paletteButton.mapToItem(host, localX, localY)
                paletteContextMenu.openForActions([
                    { "text": "隐藏调色按钮", "action": "hidePalette", "available": true }
                ], p.x, p.y)
            }
        }

        IconButton {
            id: themeButton
            width: Core.Theme.dp(28)
            height: Core.Theme.dp(24)
            iconName: Core.Theme.mode === "dark" ? "sun" : "moon"
            strokeWidth: 0.90
            noBorder: true
            tooltip: "日夜切换"
            onClicked: {
                const next = Core.Theme.mode === "dark" ? "light" : "dark"
                const p = themeButton.mapToItem(root, themeButton.width / 2, themeButton.height / 2)
                root.themeToggleRequested(Qt.point(p.x, p.y), next)
            }
        }

        IconButton {
            width: Core.Theme.dp(28)
            height: Core.Theme.dp(24)
            accent: false
            noBorder: true
            strokeWidth: root.alwaysOnTop ? 1.0 : 0.90
            iconName: root.alwaysOnTop ? "pin-filled" : "pin"
            iconColor: root.alwaysOnTop ? (Core.Theme.mode === "dark" ? Core.Theme.white : "#20242C") : Core.Theme.color.icon
            tooltip: root.alwaysOnTop ? "取消置顶" : "窗口置顶"
            onClicked: root.alwaysOnTopRequested(!root.alwaysOnTop)
        }

        Rectangle {
            width: 1
            height: Core.Theme.dp(16)
            anchors.verticalCenter: parent.verticalCenter
            color: Core.Theme.color.hairline
        }

        IconButton { width: Core.Theme.dp(28); height: Core.Theme.dp(24); iconName: "minimize"; strokeWidth: 0.90; noBorder: true; onClicked: root.minimizeRequested() }
        IconButton { width: Core.Theme.dp(28); height: Core.Theme.dp(24); iconName: root.windowMaximized ? "restore" : "maximize"; strokeWidth: 0.90; noBorder: true; onClicked: root.toggleMaximizeRequested() }
        IconButton { width: Core.Theme.dp(28); height: Core.Theme.dp(24); iconName: "close"; strokeWidth: 0.90; noBorder: true; onClicked: root.closeRequested() }
    }

    AppContextMenu {
        id: paletteContextMenu
        parent: root.Window.window ? root.Window.window.contentItem : root
        menuWidth: Core.Theme.dp(188)
        onActionTriggered: function(action) {
            if (action === "hidePalette") {
                colorPopup.close()
                if (typeof App !== "undefined" && App && App.theme)
                    App.theme.setShowColorButton(false)
                else if (typeof App !== "undefined" && App && App.settings)
                    App.settings.setValue("ui/showColorButton", false)
            }
        }
    }


    AppMenu {
        id: menuPopup
        parent: root.Window.window ? root.Window.window.contentItem : root
        onActionTriggered: function(action, kind) { root.menuActionRequested(action, kind) }
    }

    ColorPalettePopup { id: colorPopup; parent: root.Window.window ? root.Window.window.contentItem : root }
}
