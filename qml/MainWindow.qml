import QtQuick
import QtQuick.Controls
import "core" as Core
import "window"
import "layout"
import "controls"

FramelessWindow {
    id: win
    windowKey: "main"
    bridge: App
    title: "QML 无边框框架"
    width: 1080
    height: 700
    minimumWidth: 640
    minimumHeight: 420

    titleBar.leftMenus: [
        { "text": "设置", "action": "settings" },
        { "text": "工具", "action": "tools" },
        { "text": "更新", "action": "update" },
        { "text": "关于", "action": "about" }
    ]

    Row {
        id: mainRow
        anchors.fill: parent

        ResizableSideNav {
            id: sideNav
            height: parent.height
            width: (typeof App !== "undefined" && App && App.settings) ? Math.max(0, Math.min(App.settings.valueOr("layout/navWidth", Core.Theme.metrics.navWidthDefault), Core.Theme.metrics.navWidthMax)) : Core.Theme.metrics.navWidthDefault
            cornerRadius: win.cornerRadius
            onCurrentPageChanged: pageHost.showPage(currentPage)
        }

        PageHost {
            id: pageHost
            width: parent.width - sideNav.width
            height: parent.height
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onTapped: if (trayMenu.visible) trayMenu.closeMenu()
        }
    }

    Binding {
        target: win.titleBar
        property: "navHidden"
        value: sideNav.width === 0
    }

    Connections {
        target: win.titleBar
        function onActivateRequested() {
            if (trayMenu.visible) trayMenu.closeMenu()
        }
        function onToggleNavRequested() {
            sideNav.toggle()
        }
        function onMenuActionRequested(action, kind) {
            if (kind === "page") {
                sideNav.restore()
                sideNav.currentPage = action
            } else {
                if (typeof App !== "undefined" && App && App.dialogs)
                    App.dialogs.openChild(win, action, ({}))
            }
        }
    }

    TrayMenuWindow { id: trayMenu }

    MouseArea {
        anchors.fill: parent
        z: 999999
        visible: trayMenu.visible
        enabled: visible
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: function(mouse) {
            trayMenu.closeMenu()
            mouse.accepted = true
        }
    }

    Connections {
        target: (typeof App !== "undefined" && App && App.tray) ? App.tray : null
        function onTrayContextMenuRequested(x, y) {
            trayMenu.toggleAt(x, y)
        }
        function onTrayPrimaryClicked() {
            if (trayMenu.visible)
                trayMenu.closeMenu()
            else if (typeof App !== "undefined" && App && App.tray)
                App.tray.showMainWindow()
        }
    }


    Component.onCompleted: {
        if (typeof App !== "undefined" && App && App.tray)
            App.tray.registerWindow(win)
    }

    onWindowEvent: function(type, payload) {
        if (typeof App !== "undefined" && App && App.window)
            App.window.handleWindowEvent(windowKey, type, payload)
    }
}
