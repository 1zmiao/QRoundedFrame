import QtQuick
import "core" as Core
import "window"
import "layout"
import FramelessNative 1.0

AppWindow {
    id: win
    windowKey: "main"
    bridge: App
    title: Core.AppInfo.windowTitle
    width: 936
    height: 749
    minimumWidth: 640
    minimumHeight: 420

    leftMenus: Core.AppInfo.mainMenus

    NativeChildWindowManager {
        id: nativeChildWindowManager
        bridge: App
        Component.onCompleted: {
            if (App && App.dialogs && App.dialogs.setNativeChildWindowManager)
                App.dialogs.setNativeChildWindowManager(nativeChildWindowManager)
        }
        Component.onDestruction: {
            if (App && App.dialogs && App.dialogs.setNativeChildWindowManager)
                App.dialogs.setNativeChildWindowManager(null)
        }
    }

    MainWindowContent {
        anchors.fill: parent
        windowObject: win
    }
}
