import QtQuick
import QtQuick.Window
import "../core" as Core

Window {
    id: root
    flags: Qt.ToolTip | Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | Qt.NoDropShadowWindowHint
    color: "transparent"
    visible: false

    property int shadowMargin: Core.Theme.dp(10)
    property int menuWidth: Core.Theme.dp(178)
    property int menuHeight: Core.Theme.dp(104)
    width: menuWidth + shadowMargin * 2
    height: menuHeight + shadowMargin * 2

    function openAt(px, py) {
        const margin = Core.Theme.dp(6)
        let nx = px - width + Core.Theme.dp(8)
        let ny = py - height - Core.Theme.dp(8)
        if (nx < margin) nx = margin
        if (ny < margin) ny = py + Core.Theme.dp(8)
        x = nx
        y = ny
        visible = true
    }

    function toggleAt(px, py) {
        if (visible)
            closeMenu()
        else
            openAt(px, py)
    }

    function closeMenu() { visible = false }

    Rectangle {
        anchors.fill: panel
        anchors.topMargin: Core.Theme.dp(5)
        anchors.leftMargin: Core.Theme.dp(2)
        anchors.rightMargin: Core.Theme.dp(2)
        radius: Core.Theme.radius.popup
        color: Core.Theme.color.shadow
        opacity: Core.Theme.mode === "dark" ? 0.36 : 0.18
    }

    Rectangle {
        anchors.fill: panel
        anchors.topMargin: Core.Theme.dp(2)
        anchors.leftMargin: Core.Theme.dp(1)
        anchors.rightMargin: Core.Theme.dp(1)
        radius: Core.Theme.radius.popup
        color: Core.Theme.color.shadow
        opacity: Core.Theme.mode === "dark" ? 0.22 : 0.10
    }

    Rectangle {
        id: panel
        x: root.shadowMargin
        y: root.shadowMargin
        width: root.menuWidth
        height: root.menuHeight
        radius: Core.Theme.radius.popup
        color: Core.Theme.color.card
        border.color: Core.Theme.color.outlineAccent
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: Core.Theme.dp(7)
            spacing: Core.Theme.dp(4)

            MenuAction {
                text: "居中主窗口"
                iconName: "target"
                onTriggered: {
                    root.closeMenu()
                    if (typeof App !== "undefined" && App && App.tray) App.tray.centerMainWindow()
                }
            }

            Rectangle { width: parent.width; height: 1; color: Core.Theme.color.hairline; opacity: 0.8 }

            MenuAction {
                text: "退出"
                iconName: "close"
                onTriggered: {
                    root.closeMenu()
                    if (typeof App !== "undefined" && App && App.tray) App.tray.exitApplication()
                }
            }
        }
    }

    onActiveChanged: if (!active && visible) closeDelay.restart()
    Timer { id: closeDelay; interval: 90; repeat: false; onTriggered: if (!root.active) root.visible = false }
    Timer {
        id: outsideClickWatch
        interval: 45
        repeat: true
        running: root.visible
        onTriggered: {
            if (typeof App !== "undefined" && App && App.tray && App.tray.mousePressedOutside(root.x, root.y, root.width, root.height))
                root.closeMenu()
        }
    }

    component MenuAction: Item {
        id: item
        property string text: ""
        property string iconName: ""
        signal triggered()
        width: parent ? parent.width : Core.Theme.dp(160)
        height: Core.Theme.dp(38)
        property bool hovered: mouse.containsMouse

        Rectangle {
            anchors.fill: parent
            radius: Core.Theme.radius.button
            color: mouse.pressed ? Core.Theme.color.controlPressed : (item.hovered ? Core.Theme.color.controlHover : "transparent")
        }

        Canvas {
            id: iconCanvas
            x: Core.Theme.dp(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Core.Theme.dp(16)
            height: Core.Theme.dp(16)
            antialiasing: true
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                Core.Icons.drawIcon(ctx, item.iconName, width, height, Core.Theme.color.icon, 1.02)
            }
            Connections {
                target: Core.Theme
                function onModeChanged() { iconCanvas.requestPaint() }
                function onPrimaryChanged() { iconCanvas.requestPaint() }
                function onFontScaleChanged() { iconCanvas.requestPaint() }
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: Core.Theme.dp(36)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: item.text
            color: Core.Theme.color.text
            font.pixelSize: Core.Theme.fontSize.control
            elide: Text.ElideRight
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: item.triggered()
        }
    }
}
