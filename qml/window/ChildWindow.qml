import QtQuick
import QtQuick.Window
import "."

FramelessWindow {
    id: child
    bridge: App
    showNavToggle: false
    title: pageTitle
    width: 760
    height: 520
    minimumWidth: 520
    minimumHeight: 360

    property var parentWindow: null
    property string pageSource: ""
    property string pageTitle: "子窗口"

    modality: Qt.NonModal

    Loader {
        anchors.fill: parent
        asynchronous: true
        source: child.pageSource
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

    onParentWindowChanged: applyParentWindow()
    Component.onCompleted: applyParentWindow()
}
