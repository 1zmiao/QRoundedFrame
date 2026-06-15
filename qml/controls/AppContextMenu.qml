import QtQuick
import "../core" as Core

Item {
    id: root

    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    visible: false
    enabled: visible
    z: 100000

    property var textTarget: null
    property var actions: []
    property real menuX: 0
    property real menuY: 0
    property int menuWidth: Core.Theme.dp(178)
    signal actionPrepared(string action)
    signal actionTriggered(string action)

    function openForTextField(target, px, py) {
        textTarget = target
        actions = []
        _openAt(px, py)
    }

    function openForActions(items, px, py) {
        if (visible) {
            close()
            return
        }
        textTarget = null
        actions = items || []
        _openAt(px, py)
    }

    function close() {
        if (!visible)
            return
        visible = false
        textTarget = null
        actions = []
        if (typeof App !== "undefined" && App && App.trimMemory)
            Qt.callLater(App.trimMemory)
    }

    function _openAt(px, py) {
        const menuHeight = Math.max(Core.Theme.dp(80), menuRect.implicitHeight)
        const maxX = Math.max(Core.Theme.dp(6), root.width - root.menuWidth - Core.Theme.dp(6))
        const maxY = Math.max(Core.Theme.dp(6), root.height - menuHeight - Core.Theme.dp(6))
        menuX = Math.max(Core.Theme.dp(6), Math.min(maxX, px))
        menuY = Math.max(Core.Theme.dp(6), Math.min(maxY, py))
        visible = true
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        onPressed: function(mouse) {
            const inside = mouse.x >= menuRect.x && mouse.x <= menuRect.x + menuRect.width
                           && mouse.y >= menuRect.y && mouse.y <= menuRect.y + menuRect.height
            if (!inside)
                root.close()
            mouse.accepted = true
        }
        onPositionChanged: function(mouse) { mouse.accepted = true }
        onReleased: function(mouse) { mouse.accepted = true }
        onClicked: function(mouse) { mouse.accepted = true }
        onWheel: function(wheel) { wheel.accepted = true }
    }

    PanelShadow {
        id: menuShadow
        x: menuRect.x
        y: menuRect.y
        width: menuRect.width
        height: menuRect.height
        radius: menuRect.radius
        visible: root.visible
        z: 1
    }

    Rectangle {
        id: menuRect
        z: 2
        x: root.menuX
        y: root.menuY
        width: root.menuWidth
        implicitHeight: menuColumn.implicitHeight + Core.Theme.dp(12)
        height: implicitHeight
        radius: Core.Theme.radius.popup
        antialiasing: true
        color: Core.Theme.color.card
        border.width: 1
        border.color: Core.Theme.mode === "dark" ? Core.Theme.alpha(Qt.lighter(Core.Theme.primary, 1.65), 0.88) : Core.Theme.color.outlineAccent
        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
        Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }

        Column {
            id: menuColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Core.Theme.dp(6)
            spacing: Core.Theme.dp(3)

            Repeater {
                model: root.actions.length > 0 ? root.actions : []
                delegate: ContextMenuItem {
                    width: parent.width
                    text: modelData.text || ""
                    shortcut: modelData.shortcut || ""
                    available: modelData.available === undefined ? true : modelData.available
                    onPrepared: root.actionPrepared(modelData.action || modelData.text || "")
                    onTriggered: {
                        root.actionTriggered(modelData.action || modelData.text || "")
                        root.close()
                    }
                }
            }

            Item {
                width: parent.width
                height: root.actions.length > 0 ? 0 : textMenuColumn.implicitHeight
                visible: root.actions.length === 0

                Column {
                    id: textMenuColumn
                    width: parent.width
                    spacing: Core.Theme.dp(3)

                    ContextMenuItem {
                        width: parent.width
                        text: "剪切"
                        shortcut: "Ctrl+X"
                        available: root.textTarget && !root.textTarget.readOnly && root.textTarget.selectedText.length > 0
                        onTriggered: { root.textTarget.cut(); root.close() }
                    }

                    ContextMenuItem {
                        width: parent.width
                        text: "复制"
                        shortcut: "Ctrl+C"
                        available: root.textTarget && root.textTarget.selectedText.length > 0
                        onTriggered: { root.textTarget.copy(); root.close() }
                    }

                    ContextMenuItem {
                        width: parent.width
                        text: "粘贴"
                        shortcut: "Ctrl+V"
                        available: root.textTarget && !root.textTarget.readOnly
                        onTriggered: { root.textTarget.paste(); root.close() }
                    }

                    Rectangle { width: parent.width; height: 1; color: Core.Theme.color.hairline; opacity: 0.8 }

                    ContextMenuItem {
                        width: parent.width
                        text: "全选"
                        shortcut: "Ctrl+A"
                        available: root.textTarget && root.textTarget.text.length > 0
                        onTriggered: { root.textTarget.selectAll(); root.close() }
                    }

                    Rectangle { width: parent.width; height: 1; color: Core.Theme.color.hairline; opacity: 0.8 }

                    ContextMenuItem {
                        width: parent.width
                        text: root.textTarget && root.textTarget.encrypted ? "改为明文存储" : "改为密文存储"
                        shortcut: ""
                        available: root.textTarget && root.textTarget.storageKey && root.textTarget.storageKey.length > 0
                        onTriggered: {
                            if (root.textTarget && root.textTarget.setEncryptedStorage)
                                root.textTarget.setEncryptedStorage(!root.textTarget.encrypted)
                            root.close()
                        }
                    }
                }
            }
        }
    }
}
