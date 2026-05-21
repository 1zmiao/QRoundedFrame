import QtQuick
import QtQuick.Window
import "../core" as Core

Window {
    id: root
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | Qt.NoDropShadowWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    visible: false

    property int shadowMargin: Core.Theme.dp(18)
    property int menuWidth: Core.Theme.dp(184)
    property int menuHeight: Core.Theme.dp(104)
    property double openedAt: 0
    property point lastCursorPos: Qt.point(0, 0)
    width: menuWidth + shadowMargin * 2
    height: menuHeight + shadowMargin * 2

    function openAt(px, py) {
        const margin = Core.Theme.dp(6)
        const area = (typeof App !== "undefined" && App && App.tray && App.tray.availableGeometryAt)
            ? App.tray.availableGeometryAt(px, py) : ({})
        let panelX = px - root.menuWidth
        let panelY = py - root.menuHeight
        if (area && area.w > 0 && area.h > 0) {
            const leftLimit = area.x + margin
            const topLimit = area.y + margin
            const rightLimit = area.x + area.w - root.menuWidth - margin
            const bottomLimit = area.y + area.h - root.menuHeight - margin
            panelX = px - root.menuWidth >= leftLimit ? px - root.menuWidth : px
            panelY = py - root.menuHeight >= topLimit ? py - root.menuHeight : py
            panelX = Math.max(leftLimit, Math.min(rightLimit, panelX))
            panelY = Math.max(topLimit, Math.min(bottomLimit, panelY))
        } else {
            if (panelX < margin)
                panelX = px
            if (panelY < margin)
                panelY = py
        }
        x = panelX - root.shadowMargin
        y = panelY - root.shadowMargin
        lastCursorPos = Qt.point(px, py)
        openedAt = Date.now()
        visible = true
        if (typeof App !== "undefined" && App && App.tray && App.tray.raiseTrayMenuWindow)
            App.tray.raiseTrayMenuWindow(root)
    }

    function toggleAt(px, py) {
        if (visible)
            closeMenu()
        else
            openAt(px, py)
    }

    function closeMenu() { visible = false }

    PanelShadow {
        x: panel.x
        y: panel.y
        width: panel.width
        height: panel.height
        radius: panel.radius
        visible: root.visible
        z: 0
    }

    Rectangle {
        id: panel
        z: 1
        x: root.shadowMargin
        y: root.shadowMargin
        width: root.menuWidth
        height: root.menuHeight
        radius: Core.Theme.radius.popup
        antialiasing: true
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

    Timer {
        id: outsideClickWatch
        interval: 45
        repeat: true
        running: root.visible
        onTriggered: {
            if (Date.now() - root.openedAt < 180)
                return
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
