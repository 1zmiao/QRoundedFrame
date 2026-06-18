import QtQuick
import QtQuick.Window
import "."

AppWindow {
    id: child
    bridge: App
    autoRestoreWindowState: false
    autoShow: false
    destroyOnChildClose: true
    showNavToggle: false
    showColorButton: false
    showThemeButton: false
    showPinButton: childTopmostEnabled
    showTitleBarResourceStats: false
    title: pageTitle
    width: 760
    height: 520
    minimumWidth: 520
    minimumHeight: 360

    property var parentWindow: null
    property url pageSource: ""
    property string pageTitle: "子窗口"
    property int taskId: -1
    property string taskType: "default"
    property var pageProperties: ({})
    property bool childTopmostEnabled: false
    property bool contentReleased: false

    modality: Qt.NonModal

    Loader {
        id: pageLoader
        anchors.fill: parent
        asynchronous: false
        active: !child.contentReleased
        source: child.contentReleased ? "" : child.pageSource
        onLoaded: child.applyPageProperties()
        onStatusChanged: {
            if (status === Loader.Error)
                console.warn("NativeChildWindow page load error", child.windowKey, child.pageSource)
        }
    }

    function prepareContent(sourceUrl) {
        alwaysOnTop = false
        _childCloseScheduled = false
        pageSource = sourceUrl
        contentReleased = false
    }

    function applyPageProperties() {
        if (!pageLoader.item)
            return
        const props = pageProperties || ({})
        if (props.taskId !== undefined && pageLoader.item.taskId !== undefined)
            pageLoader.item.taskId = Number(props.taskId)
        if (props.taskType !== undefined && pageLoader.item.taskType !== undefined)
            pageLoader.item.taskType = String(props.taskType)
        if (taskId > 0 && pageLoader.item.taskId !== undefined)
            pageLoader.item.taskId = taskId
        if (taskType.length > 0 && pageLoader.item.taskType !== undefined)
            pageLoader.item.taskType = taskType
    }

    function releaseContent() {
        contentReleased = true
        pageSource = ""
        pageLoader.source = ""
        pageLoader.active = false
    }

    function applyParentWindow() {
        if (parentWindow !== null && parentWindow !== undefined) {
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
        if (!enabled && childTopmostEnabled && titleBar && titleBar.pinButtonItem)
            unregisterNativeClickableItem(titleBar.pinButtonItem)
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
