import QtQuick
import "../core" as Core
import "../controls"

Item {
    id: root

    property var windowObject
    property bool inlineWindowsEnabled: true
    property string pendingInlinePageKey: ""
    property var pendingInlineProps: ({})
    property bool trayMenuVisible: trayMenuLoader.item ? trayMenuLoader.item.visible : false
    readonly property real devicePixelRatio: Math.max(1.0, root.windowObject && root.windowObject.screen ? root.windowObject.screen.devicePixelRatio : 1.0)
    readonly property real physicalPixel: 1.0 / devicePixelRatio

    function snapToPhysicalPixel(value) {
        return Math.round(value / physicalPixel) * physicalPixel
    }

    function childTitleFor(pageKey) {
        return Core.AppInfo.pageTitle(pageKey)
    }

    function savedCurrentPage() {
        if (typeof App === "undefined" || !App || !App.settings)
            return "home"
        const page = String(App.settings.valueOr("ui/lastPage", "home") || "home")
        return Core.AppInfo.pageSource(page).length > 0 ? page : "home"
    }

    function showMainPage(pageKey, persist) {
        const page = Core.AppInfo.pageSource(pageKey).length > 0 ? String(pageKey) : "home"
        sideNav.currentPage = page
        pageHost.showPage(page)
        if (persist && typeof App !== "undefined" && App && App.settings)
            App.settings.setValue("ui/lastPage", page)
    }

    function openChildByPolicy(pageKey, props, mode) {
        const openMode = mode || "auto"
        const lowMemory = (typeof App !== "undefined" && App && App.performance) ? App.performance.effectiveProfile === "low-memory" : false
        const useInline = root.inlineWindowsEnabled && (openMode === "inline" || (openMode === "auto" && lowMemory))
        if (useInline) {
            const safeProps = props || ({})
            if (inlineWindowManagerLoader.item) {
                inlineWindowManagerLoader.item.openPage(pageKey, childTitleFor(pageKey), safeProps)
            } else {
                pendingInlinePageKey = String(pageKey || "about")
                pendingInlineProps = safeProps
                inlineWindowManagerLoader.active = true
            }
        } else if (typeof App !== "undefined" && App && App.dialogs) {
            App.dialogs.openChild(root.windowObject, pageKey, props || ({}))
        }
    }

    function prepareOpenChildByPolicy(pageKey, mode) {
        const openMode = mode || "auto"
        const lowMemory = (typeof App !== "undefined" && App && App.performance) ? App.performance.effectiveProfile === "low-memory" : false
        const useInline = root.inlineWindowsEnabled && (openMode === "inline" || (openMode === "auto" && lowMemory))
        if (useInline) {
            inlineWindowManagerLoader.active = true
        } else if (typeof App !== "undefined" && App && App.dialogs && App.dialogs.prepareChild) {
            App.dialogs.prepareChild(pageKey)
        }
    }

    function ensureTrayMenu() {
        if (!trayMenuLoader.item)
            trayMenuLoader.active = true
        return trayMenuLoader.item
    }

    function closeTrayMenu() {
        if (trayMenuLoader.item)
            trayMenuLoader.item.closeMenu()
    }

    function smokeShowPage(pageKey) {
        if (!pageKey || pageKey.length <= 0)
            return false
        root.showMainPage(String(pageKey), true)
        return true
    }

    function toggleTrayMenuAt(x, y) {
        const menu = ensureTrayMenu()
        if (menu)
            menu.toggleAt(x, y)
    }

    Row {
        id: mainRow
        anchors.fill: parent

        ResizableSideNav {
            id: sideNav
            height: parent.height
            width: sideNav.snapToPhysicalPixel((typeof App !== "undefined" && App && App.settings)
                   ? Math.max(0, Math.min(App.settings.valueOr("layout/navWidth", Core.Theme.metrics.navWidthDefault), Core.Theme.metrics.navWidthMax))
                   : Core.Theme.metrics.navWidthDefault)
            cornerRadius: root.windowObject ? root.windowObject.cornerRadius : Core.Theme.radius.window
            currentPage: root.savedCurrentPage()
            onPageIntent: function(page) { pageHost.preparePage(page) }
            onCurrentPageChanged: root.showMainPage(currentPage, true)
        }

        PageHost {
            id: pageHost
            width: Math.max(0, Math.round(parent.width - sideNav.width))
            height: parent.height
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onTapped: if (root.trayMenuVisible) root.closeTrayMenu()
        }
    }

    Binding {
        target: root.windowObject ? root.windowObject.titleBar : null
        property: "navHidden"
        value: sideNav.width === 0
    }

    Connections {
        target: root.windowObject ? root.windowObject.titleBar : null
        function onActivateRequested() {
            if (root.trayMenuVisible)
                root.closeTrayMenu()
        }
        function onToggleNavRequested() {
            sideNav.toggle()
        }
        function onMenuActionRequested(action, kind) {
            if (kind === "page") {
                root.showMainPage(action, true)
            } else {
                root.openChildByPolicy(action, ({}), "auto")
            }
        }
        function onMenuActionPrepared(action, kind) {
            if (kind !== "child")
                return
            if (typeof App !== "undefined" && App && App.dialogs && App.dialogs.prepareChild)
                App.dialogs.prepareChild(action)
        }
    }

    Loader {
        id: trayMenuLoader
        active: false
        sourceComponent: TrayMenuWindow {}
    }

    Loader {
        id: inlineWindowManagerLoader
        x: Math.round(mainRow.x + sideNav.width)
        y: mainRow.y
        width: Math.round(pageHost.width)
        height: pageHost.height
        z: 20
        active: false
        sourceComponent: InlineWindowManager {
            width: inlineWindowManagerLoader.width
            height: inlineWindowManagerLoader.height
        }
        onLoaded: {
            if (item && root.pendingInlinePageKey.length > 0) {
                const key = root.pendingInlinePageKey
                const props = root.pendingInlineProps || ({})
                root.pendingInlinePageKey = ""
                root.pendingInlineProps = ({})
                item.openPage(key, root.childTitleFor(key), props)
            }
        }
    }

    Connections {
        target: inlineWindowManagerLoader.item
        function onWindowCountChanged() {
            if (!inlineWindowManagerLoader.item || inlineWindowManagerLoader.item.windowCount !== 0)
                return
            Qt.callLater(function() {
                if (inlineWindowManagerLoader.item && inlineWindowManagerLoader.item.windowCount === 0) {
                    inlineWindowManagerLoader.active = false
                    if (typeof App !== "undefined" && App && App.trimMemoryAfterInlineWindowsClosed)
                        Qt.callLater(App.trimMemoryAfterInlineWindowsClosed)
                }
            })
        }
    }

    Connections {
        target: Core.InlineWindowBus
        function onPrepareChildRequested(pageKey, mode) {
            root.prepareOpenChildByPolicy(pageKey, mode)
        }
        function onOpenChildRequested(pageKey, mode, props) {
            root.openChildByPolicy(pageKey, props, mode)
        }
    }

    Connections {
        target: (typeof App !== "undefined" && App) ? App : null
        function onPrepareChildRequested(pageKey, mode) {
            root.prepareOpenChildByPolicy(pageKey, mode)
        }
        function onOpenChildRequested(pageKey, mode, props) {
            root.openChildByPolicy(pageKey, props, mode)
        }
    }

    MouseArea {
        anchors.fill: parent
        z: 999999
        visible: root.trayMenuVisible
        enabled: visible
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: function(mouse) {
            root.closeTrayMenu()
            mouse.accepted = true
        }
    }

    Connections {
        target: (typeof App !== "undefined" && App && App.tray) ? App.tray : null
        function onTrayContextMenuRequested(x, y) {
            root.toggleTrayMenuAt(x, y)
        }
        function onTrayPrimaryClicked() {
            if (root.trayMenuVisible)
                root.closeTrayMenu()
            else if (typeof App !== "undefined" && App && App.tray)
                App.tray.showMainWindow()
        }
    }

    Connections {
        target: root.windowObject
        function onWindowEvent(type, payload) {
            if (typeof App !== "undefined" && App && App.window)
                App.window.handleWindowEvent(root.windowObject.windowKey, type, payload)
        }
    }

    Component.onCompleted: {
        if (typeof App !== "undefined" && App && App.tray)
            App.tray.registerWindow(root.windowObject)
        if (typeof App !== "undefined" && App && App.logRuntime)
            App.logRuntime("main content initial page=" + sideNav.currentPage)
        root.showMainPage(sideNav.currentPage, false)
    }
}
