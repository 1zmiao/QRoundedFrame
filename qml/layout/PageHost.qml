import QtQuick

Item {
    id: root
    property string currentPage: "home"

    function showPage(page) {
        currentPage = page
    }

    Loader {
        id: pageLoader
        anchors.fill: parent
        asynchronous: true
        active: true
        source: {
            if (root.currentPage === "settings") return "../pages/SettingsPage.qml"
            if (root.currentPage === "tools") return "../pages/ToolsPage.qml"
            if (root.currentPage === "update") return "../pages/UpdatePage.qml"
            if (root.currentPage === "about") return "../pages/AboutPage.qml"
            return "../pages/HomePage.qml"
        }
    }
}
