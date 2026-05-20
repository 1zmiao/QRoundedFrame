import QtQuick
import QtQuick.Controls
import "../core" as Core

Popup {
    id: root
    width: Core.Theme.dp(196)
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: Core.Theme.dp(8)
    enter: Transition {}
    exit: Transition {}

    property string actionName: ""
    property double _closedAt: 0
    property string _closedActionName: ""
    property bool _suppressCloseStamp: false
    signal actionTriggered(string action, string kind)

    onClosed: {
        if (!root._suppressCloseStamp) {
            root._closedAt = Date.now()
            root._closedActionName = root.actionName
        }
        root._suppressCloseStamp = false
    }

    function isAboutMenu() { return actionName === "about" }

    function actionTitle(action) {
        if (action === "settings") return "设置"
        if (action === "tools") return "工具"
        if (action === "update") return "更新"
        if (action === "about") return "关于"
        return action
    }

    background: Item {
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: Core.Theme.dp(4)
            anchors.leftMargin: Core.Theme.dp(2)
            anchors.rightMargin: Core.Theme.dp(2)
            radius: Core.Theme.radius.popup
            color: Core.Theme.color.shadow
            opacity: Core.Theme.mode === "dark" ? 0.30 : 0.14
        }
        Rectangle {
            anchors.fill: parent
            radius: Core.Theme.radius.popup
            color: Core.Theme.color.card
            border.color: Core.Theme.color.outlineAccent
            border.width: 1
        }
    }

    contentItem: Column {
        id: menuColumn
        width: root.width - root.leftPadding - root.rightPadding
        spacing: Core.Theme.dp(4)

        Text {
            width: parent.width
            leftPadding: Core.Theme.dp(8)
            topPadding: Core.Theme.dp(2)
            bottomPadding: Core.Theme.dp(4)
            text: root.isAboutMenu() ? "关于" : root.actionTitle(root.actionName)
            color: Core.Theme.color.mutedText
            font.pixelSize: Core.Theme.fontSize.small
            font.bold: true
        }

        MenuRow {
            width: parent.width
            iconName: root.isAboutMenu() ? "about" : "dialog"
            text: root.isAboutMenu() ? "关于" : "打开子窗口"
            subText: root.isAboutMenu() ? "打开独立说明面板" : "打开独立无边框子窗口"
            onTriggered: {
                root.close()
                root.actionTriggered(root.actionName, "child")
            }
        }

        MenuRow {
            width: parent.width
            iconName: "home"
            text: root.isAboutMenu() ? "在主界面查看" : "切换到主界面页面"
            subText: root.isAboutMenu() ? "在主界面打开关于说明" : "在主界面切换页面"
            onTriggered: {
                root.close()
                root.actionTriggered(root.actionName, "page")
            }
        }
    }

    component MenuRow: Item {
        id: row
        property string iconName: ""
        property string text: ""
        property string subText: ""
        property bool hovered: mouse.containsMouse
        signal triggered()

        height: Core.Theme.dp(42)

        Rectangle {
            anchors.fill: parent
            radius: Core.Theme.radius.button
            color: mouse.pressed ? Core.Theme.color.controlPressed : (row.hovered ? Core.Theme.color.controlHover : "transparent")
        }

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: Core.Theme.dp(7)
            anchors.verticalCenter: parent.verticalCenter
            width: Core.Theme.dp(26)
            height: Core.Theme.dp(26)
            radius: Core.Theme.radius.button
            color: row.hovered ? Core.Theme.primarySoftHover : Core.Theme.primarySoft
            Canvas {
                id: rowIcon
                anchors.centerIn: parent
                width: Core.Theme.dp(14)
                height: Core.Theme.dp(14)
                antialiasing: true
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    Core.Icons.drawIcon(ctx, row.iconName, width, height, Core.Theme.mode === "dark" ? Core.Theme.white : Core.Theme.primaryStrong, 1.0)
                }
                Connections {
                    target: Core.Theme
                    function onModeChanged() { rowIcon.requestPaint() }
                    function onPrimaryChanged() { rowIcon.requestPaint() }
                }
            }
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: Core.Theme.dp(40)
            anchors.right: parent.right
            anchors.rightMargin: Core.Theme.dp(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text { text: row.text; color: Core.Theme.color.text; font.pixelSize: Core.Theme.fontSize.control; elide: Text.ElideRight; width: parent.width }
            Text { text: row.subText; color: Core.Theme.color.mutedText; font.pixelSize: Core.Theme.fontSize.tiny; elide: Text.ElideRight; width: parent.width }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.triggered()
        }
    }

    function openFor(action, item) {
        if (root.visible && actionName === action) {
            root.close()
            return
        }
        if (!root.visible && root._closedActionName === action && Date.now() - root._closedAt < 220)
            return
        actionName = action
        const p = item.mapToItem(root.parent, 0, item.height + Core.Theme.dp(4))
        const maxX = root.parent ? Math.max(Core.Theme.dp(8), root.parent.width - root.width - Core.Theme.dp(8)) : p.x
        const menuHeight = root.contentItem ? root.contentItem.implicitHeight + root.topPadding + root.bottomPadding : Core.Theme.dp(118)
        const maxY = root.parent ? Math.max(Core.Theme.dp(8), root.parent.height - menuHeight - Core.Theme.dp(8)) : p.y
        x = Math.max(Core.Theme.dp(8), Math.min(maxX, p.x))
        y = Math.max(Core.Theme.dp(8), Math.min(maxY, p.y))
        open()
    }
}
