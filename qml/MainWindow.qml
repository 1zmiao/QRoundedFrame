import QtQuick
import "core" as Core
import "window"
import "layout"

FramelessWindow {
    id: win
    windowKey: "main"
    bridge: App
    title: Core.AppInfo.windowTitle
    width: 936
    height: 749
    minimumWidth: 640
    minimumHeight: 420

    titleBar.leftMenus: Core.AppInfo.mainMenus

    MainWindowContent {
        anchors.fill: parent
        windowObject: win
    }
}
