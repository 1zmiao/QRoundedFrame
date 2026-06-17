pragma Singleton
import QtQuick

QtObject {
    readonly property string windowTitle: "QML无边框窗口模板"
    readonly property var mainMenuKeys: ["settings", "tools", "update", "about"]
    readonly property var navPageKeys: ["home", "tools", "update", "about"]
    // 入口标题/图标优先从 Python 页面注册表读取，避免 DialogService、导航、菜单各写一份。
    // 下面的 fallback 只用于 App 尚未注入或加载异常时兜底，不作为新的文案来源。
    property var mainMenus: [
        { "text": pageTitle("settings"), "action": "settings" },
        { "text": pageTitle("tools"), "action": "tools" },
        { "text": pageTitle("update"), "action": "update" },
        { "text": pageTitle("about"), "action": "about" }
    ]

    function pageTitle(pageKey) {
        if (typeof App !== "undefined" && App && App.pageTitle)
            return App.pageTitle(String(pageKey || ""))
        if (pageKey === "settings") return "设置"
        if (pageKey === "tools") return "工具"
        if (pageKey === "update") return "更新"
        if (pageKey === "about") return "关于"
        if (pageKey === "inline-demo") return "页内子窗口"
        return "首页"
    }

    function pageSource(pageKey) {
        if (typeof App !== "undefined" && App && App.pageSource)
            return App.pageSource(String(pageKey || ""))
        if (pageKey === "settings") return "../pages/SettingsPage.qml"
        if (pageKey === "tools") return "../pages/ToolsPage.qml"
        if (pageKey === "update") return "../pages/UpdatePage.qml"
        if (pageKey === "about") return "../pages/AboutPage.qml"
        if (pageKey === "inline-demo") return "../pages/InlineDemoPage.qml"
        return "../pages/HomePage.qml"
    }

    function pageIcon(pageKey) {
        if (typeof App !== "undefined" && App && App.pageIcon)
            return App.pageIcon(String(pageKey || ""))
        if (pageKey === "settings") return "settings"
        if (pageKey === "tools") return "tools"
        if (pageKey === "update") return "update"
        if (pageKey === "about") return "about"
        if (pageKey === "inline-demo") return "dialog"
        return "home"
    }
}
