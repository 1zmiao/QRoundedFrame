import QtQuick
import "../core" as Core
import "../controls"

Item {
    id: root

    property int expandedWidth: Core.Theme.metrics.navWidthDefault
    property int compactWidth: Core.Theme.metrics.navIconWidth
    property int minWidthBeforeHidden: Core.Theme.dp(18)
    property int restoreWidth: expandedWidth
    property string currentPage: "home"
    property real startWidth: width
    property int cornerRadius: Core.Theme.radius.window

    function hide() {
        if (width > compactWidth)
            restoreWidth = width
        width = 0
        App.settings.setValue("layout/navWidth", width)
    }

    function restore() {
        width = restoreWidth > compactWidth ? restoreWidth : expandedWidth
        App.settings.setValue("layout/navWidth", width)
    }

    function toggle() {
        if (width <= 0)
            restore()
        else
            hide()
    }

    function applyWidth(next) {
        if (next < minWidthBeforeHidden)
            width = 0
        else if (next < compactWidth)
            width = compactWidth
        else
            width = Math.max(compactWidth, Math.min(Core.Theme.dp(260), next))
    }

    Item {
        id: bgLayer
        anchors.fill: parent
        visible: root.width > 0
        clip: true

        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            antialiasing: true
            color: Core.Theme.color.sidebar
        }
        BackgroundRipple { radius: root.cornerRadius }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: root.cornerRadius + 2
            color: Core.Theme.color.sidebar
        }
        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: root.cornerRadius + 2
            color: Core.Theme.color.sidebar
        }
    }

    Column {
        id: navColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: settingsDock.top
        anchors.margins: Core.Theme.dp(6)
        spacing: Core.Theme.dp(4)
        visible: root.width > 0

        Repeater {
            model: [
                { "page": "home", "text": "首页", "icon": "home" },
                { "page": "tools", "text": "工具", "icon": "tools" },
                { "page": "update", "text": "更新", "icon": "update" },
                { "page": "about", "text": "关于", "icon": "about" }
            ]

            delegate: NavItem {
                width: navColumn.width
                page: modelData.page
                label: modelData.text
                iconName: modelData.icon
            }
        }
    }

    Item {
        id: settingsDock
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Core.Theme.dp(6)
        height: root.width > 0 ? Core.Theme.metrics.navItemHeight : 0
        visible: root.width > 0

        NavItem {
            anchors.fill: parent
            page: "settings"
            label: "设置"
            iconName: "settings"
        }
    }

    Rectangle {
        id: handle
        width: 4
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        color: "transparent"
        visible: root.width > 0

        DragHandler {
            target: null
            onActiveChanged: {
                if (active)
                    root.startWidth = root.width
                else
                    App.settings.setValue("layout/navWidth", root.width)
            }
            onTranslationChanged: {
                if (active)
                    root.applyWidth(root.startWidth + translation.x)
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.SplitHCursor
            acceptedButtons: Qt.NoButton
        }
    }

    component NavItem: Item {
        id: item
        property string page: ""
        property string label: ""
        property string iconName: ""
        property bool selected: page === root.currentPage
        property bool compact: root.width <= Core.Theme.metrics.navIconOnlyThreshold

        height: Core.Theme.metrics.navItemHeight

        Rectangle {
            anchors.fill: parent
            radius: Core.Theme.radius.button
            color: item.selected ? Core.Theme.color.navActive : (mouse.pressed ? Core.Theme.color.controlPressed : (mouse.containsMouse ? Core.Theme.color.controlHover : "transparent"))
            border.color: item.selected ? Core.Theme.primaryOutline : "transparent"
            border.width: item.selected ? 1 : 0
        }

        Rectangle {
            visible: item.selected && !item.compact
            width: 3
            height: Core.Theme.dp(18)
            radius: 2
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            color: Core.Theme.primary
        }

        Canvas {
            id: navIcon
            x: item.compact ? Math.round((parent.width - width) / 2) : Core.Theme.dp(11)
            anchors.verticalCenter: parent.verticalCenter
            width: Core.Theme.dp(15)
            height: width
            antialiasing: true
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                Core.Icons.drawIcon(ctx, item.iconName, width, height, item.selected ? Core.Theme.color.navSelectedIcon : Core.Theme.color.icon, 1.05)
            }
            Connections {
                target: Core.Theme
                function onModeChanged() { navIcon.requestPaint() }
                function onPrimaryChanged() { navIcon.requestPaint() }
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: Core.Theme.dp(34)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: item.label
            visible: !item.compact
            color: item.selected ? Core.Theme.color.navSelectedText : Core.Theme.color.text
            font.pixelSize: Core.Theme.fontSize.control
            font.bold: item.selected
            elide: Text.ElideRight
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.currentPage = item.page
        }
    }
}
