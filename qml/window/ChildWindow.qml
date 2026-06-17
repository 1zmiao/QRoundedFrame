import QtQuick
import QtQuick.Window
import "."

FramelessWindow {
    id: child
    bridge: App
    autoRestoreWindowState: false
    showNavToggle: false
    showColorButton: false
    showThemeButton: false
    showPinButton: childTopmostEnabled
    title: pageTitle
    width: 760
    height: 520
    minimumWidth: 520
    minimumHeight: 360

    property var parentWindow: null
    property string pageSource: ""
    property string pageTitle: "子窗口"
    property bool childTopmostEnabled: false

    modality: Qt.NonModal

    Loader {
        id: pageLoader
        anchors.fill: parent
        asynchronous: true
        source: child.pageSource
    }

    function releaseContent() {
        pageLoader.source = ""
        pageLoader.active = false
        pageSource = ""
    }

    function applyParentWindow() {
        if (parentWindow !== null && parentWindow !== undefined) {
            // Keep child windows visually related but operationally independent.
            // We intentionally do not assign transientParent here, because native
            // transient stacking can force parent/child raise order changes during drag.
            x = parentWindow.x + 80
            y = parentWindow.y + 80
        }
    }

    function refreshChildTopmostEnabled() {
        const enabled = (typeof App !== "undefined" && App && App.settings)
                        ? App.settings.valueOr("performance/childWindowTopmostEnabled", false)
                        : false
        if (childTopmostEnabled === enabled)
            return
        childTopmostEnabled = enabled
        if (!enabled && alwaysOnTop) {
            alwaysOnTop = false
            if (bridge && bridge.window)
                bridge.window.setAlwaysOnTop(child, false)
        }
    }

    onParentWindowChanged: applyParentWindow()
    Component.onCompleted: {
        refreshChildTopmostEnabled()
        applyParentWindow()
    }

    Connections {
        target: (typeof App !== "undefined" && App && App.settings) ? App.settings : null
        function onChanged(key, value) {
            if (key === "performance/childWindowTopmostEnabled")
                child.refreshChildTopmostEnabled()
        }
    }
}
