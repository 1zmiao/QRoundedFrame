import QtQuick
import QtQuick.Window
import "../core" as Core

Window {
    id: root
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.NoDropShadowWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    visible: false

    property int shadowMargin: Core.Theme.dp(18)
    property int menuWidth: Core.Theme.dp(184)
    property int menuHeight: Core.Theme.dp(104)
    property double openedAt: 0
    width: menuWidth + shadowMargin * 2
    height: menuHeight + shadowMargin * 2

    onVisibleChanged: {
        if (typeof App !== "undefined" && App && App.tray && App.tray.setTrayMenuVisible)
            App.tray.setTrayMenuVisible(visible)
    }

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
        openedAt = Date.now()
        if (typeof App !== "undefined" && App && App.tray && App.tray.resetMousePressEdge)
            App.tray.resetMousePressEdge()
        visible = true
        if (typeof App !== "undefined" && App && App.tray && App.tray.raiseTrayMenuWindow)
            App.tray.raiseTrayMenuWindow(root)
        raise()
        requestActivate()
    }

    function toggleAt(px, py) {
        if (visible)
            closeMenu()
        else
            openAt(px, py)
    }

    function closeMenu() {
        if (!visible)
            return
        visible = false
    }

    onActiveChanged: {
        // 托盘菜单是独立 Tool 窗口，部分 Windows/虚拟机环境不会稳定给它焦点。
        // 关闭交给空白点击、再次右键和菜单项本身处理，避免右键刚打开就闪退。
    }

    component OutsideMouseArea: MouseArea {
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: false
        onPressed: function(mouse) {
            root.closeMenu()
            mouse.accepted = true
        }
        onReleased: function(mouse) { mouse.accepted = true }
        onClicked: function(mouse) { mouse.accepted = true }
        onWheel: function(wheel) { wheel.accepted = true }
    }

    OutsideMouseArea {
        z: 0.5
        x: 0
        y: 0
        width: parent.width
        height: panel.y
    }

    OutsideMouseArea {
        z: 0.5
        x: 0
        y: panel.y + panel.height
        width: parent.width
        height: Math.max(0, parent.height - y)
    }

    OutsideMouseArea {
        z: 0.5
        x: 0
        y: panel.y
        width: panel.x
        height: panel.height
    }

    OutsideMouseArea {
        z: 0.5
        x: panel.x + panel.width
        y: panel.y
        width: Math.max(0, parent.width - x)
        height: panel.height
    }

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
        border.width: 1
        border.color: Core.Theme.mode === "dark" ? Core.Theme.alpha(Qt.lighter(Core.Theme.primary, 1.65), 0.88) : Core.Theme.color.outlineAccent
        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
        Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }

        Column {
            anchors.fill: parent
            anchors.margins: Core.Theme.dp(7)
            spacing: Core.Theme.dp(4)

            ContextMenuItem {
                width: parent.width
                text: "居中主窗口"
                iconName: "target"
                onTriggered: {
                    root.closeMenu()
                    if (typeof App !== "undefined" && App && App.tray)
                        App.tray.centerMainWindow()
                }
            }

            Rectangle { width: parent.width; height: 1; color: Core.Theme.color.hairline; opacity: 0.8 }

            ContextMenuItem {
                width: parent.width
                text: "退出"
                iconName: "close"
                onTriggered: {
                    root.closeMenu()
                    if (typeof App !== "undefined" && App && App.tray)
                        App.tray.exitApplication()
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
            if (typeof App !== "undefined" && App && App.tray && App.tray.mousePressedOutside(root.x + panel.x, root.y + panel.y, panel.width, panel.height))
                root.closeMenu()
        }
    }
}
