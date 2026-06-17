import QtQuick
import "../core" as Core

Item {
    id: root
    property string currentPage: ""
    property string pendingPage: ""
    property string loadedPage: ""
    property var warmedComponents: ({})
    property var warmedOrder: []
    property int pageLoadSerial: 0
    readonly property int maxPreparedPages: {
        if (typeof App !== "undefined" && App && App.performance && App.performance.effectiveProfile === "low-memory")
            return 1
        return 2
    }

    function sourceFor(page) {
        return Core.AppInfo.pageSource(page)
    }

    function logRuntime(message) {
        if (typeof App !== "undefined" && App && App.logRuntime)
            App.logRuntime(message)
    }

    function preparePage(page) {
        page = String(page || "")
        if (page.length <= 0 || page === currentPage || warmedComponents[page])
            return
        const source = root.sourceFor(page)
        if (!source || source.length <= 0)
            return
        root.evictPreparedPages(page)
        const component = Qt.createComponent(source, Component.Asynchronous)
        warmedComponents[page] = component
        warmedOrder = warmedOrder.concat([page])
        component.statusChanged.connect(function() {
            if (component.status === Component.Ready)
                root.logRuntime("page prepared key=" + page)
            else if (component.status === Component.Error)
                root.logRuntime("page prepare failed key=" + page + " error=" + component.errorString())
        })
    }

    function evictPreparedPages(nextPage) {
        while (warmedOrder.length >= maxPreparedPages) {
            const page = warmedOrder[0]
            warmedOrder = warmedOrder.slice(1)
            if (page === currentPage || page === nextPage)
                continue
            const component = warmedComponents[page]
            delete warmedComponents[page]
            if (component && component.destroy)
                component.destroy()
            root.logRuntime("page prepared cache evicted key=" + page)
            return
        }
    }

    function takePreparedComponent(page) {
        const component = warmedComponents[page]
        if (!component)
            return null
        delete warmedComponents[page]
        warmedOrder = warmedOrder.filter(function(item) { return item !== page })
        if (component.status === Component.Ready)
            return component
        root.logRuntime("page prepared not ready key=" + page + " status=" + component.status)
        if (component && component.destroy)
            component.destroy()
        return null
    }

    function clearPreparedPages() {
        const pages = warmedOrder.slice()
        warmedOrder = []
        for (let i = 0; i < pages.length; ++i) {
            const page = pages[i]
            const component = warmedComponents[page]
            delete warmedComponents[page]
            if (component && component.destroy)
                component.destroy()
        }
        if (pages.length > 0)
            root.logRuntime("page prepared cache cleared count=" + pages.length)
    }

    function showPage(page) {
        if (page === currentPage && pageLoader.active)
            return
        pendingPage = page
        const nextPage = pendingPage.length > 0 ? pendingPage : "home"
        const prepared = root.takePreparedComponent(nextPage)
        if (loadedPage.length > 0)
            root.logRuntime("page unloading key=" + loadedPage)
        const serial = ++root.pageLoadSerial
        pageLoader.source = ""
        pageLoader.sourceComponent = null
        root.currentPage = ""
        root.loadedPage = ""
        root.currentPage = nextPage
        if (serial !== root.pageLoadSerial)
            return
        if (prepared) {
            pageLoader.source = ""
            pageLoader.sourceComponent = prepared
            root.logRuntime("page using prepared component key=" + root.currentPage)
        } else {
            pageLoader.sourceComponent = null
            pageLoader.source = root.sourceFor(root.currentPage)
        }
        if (typeof App !== "undefined" && App && App.logMemorySample)
            Qt.callLater(function() { App.logMemorySample("page_" + root.currentPage) })
    }

    Loader {
        id: pageLoader
        anchors.fill: parent
        asynchronous: false
        active: root.currentPage.length > 0
        source: ""
        onStatusChanged: {
            if (status === Loader.Error)
                root.logRuntime("page load failed key=" + root.currentPage + " source=" + String(source))
            else if (status === Loader.Loading)
                root.logRuntime("page loading key=" + root.currentPage)
        }
        onItemChanged: {
            if (!item && root.loadedPage.length > 0) {
                root.logRuntime("page unloaded key=" + root.loadedPage)
                root.loadedPage = ""
            }
        }
        onLoaded: {
            root.loadedPage = root.currentPage
            root.logRuntime("page loaded key=" + root.currentPage + " source=" + String(source))
            settledTrimTimer.restart()
        }
    }

    Timer {
        id: settledTrimTimer
        interval: 450
        repeat: false
        onTriggered: {
            root.clearPreparedPages()
            if (typeof App !== "undefined" && App && App.trimMemoryAfterPageSettled)
                App.trimMemoryAfterPageSettled()
            delayedTrimTimer.restart()
        }
    }

    Timer {
        id: delayedTrimTimer
        interval: 1400
        repeat: false
        onTriggered: {
            root.clearPreparedPages()
            if (typeof App !== "undefined" && App && App.trimMemoryAfterPageSettled)
                App.trimMemoryAfterPageSettled()
        }
    }
}
