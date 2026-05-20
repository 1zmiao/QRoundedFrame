import QtQuick
import QtQuick.Controls
import "../core" as Core

Popup {
    id: root
    modal: true
    focus: true
    width: Math.min(430, parent ? Math.max(320, parent.width - 56) : 430)
    padding: 18
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property string dialogTitle: "弹窗"
    default property alias dialogContent: body.data

    function centerInHost() {
        if (!parent)
            return
        x = Math.round(Math.max(0, (parent.width - width) / 2))
        y = Math.round(Math.max(0, (parent.height - height) / 2))
    }

    function openCentered(host) {
        if (host !== undefined && host !== null)
            parent = host
        centerInHost()
        open()
        Qt.callLater(centerInHost)
    }

    onAboutToShow: centerInHost()
    onOpened: centerInHost()
    onWidthChanged: if (visible) centerInHost()
    onHeightChanged: if (visible) centerInHost()

    Overlay.modal: Rectangle {
        color: Core.Theme.mode === "dark" ? "#66000000" : "#33000000"
    }

    background: Item {
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: Core.Theme.dp(5)
            anchors.leftMargin: Core.Theme.dp(2)
            anchors.rightMargin: Core.Theme.dp(2)
            radius: Core.Theme.radius.popup
            color: Core.Theme.color.shadow
            opacity: Core.Theme.mode === "dark" ? 0.34 : 0.16
        }
        Rectangle {
            anchors.fill: parent
            radius: Core.Theme.radius.popup
            color: Core.Theme.color.card
            border.color: Core.Theme.color.outlineAccent
            border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on border.color { ColorAnimation { duration: 120 } }
        }
    }

    contentItem: Column {
        spacing: 14
        width: root.width - root.leftPadding - root.rightPadding

        Row {
            width: parent.width
            spacing: 8
            Canvas {
                id: dialogIcon
                width: Core.Theme.dp(18)
                height: Core.Theme.dp(18)
                anchors.verticalCenter: parent.verticalCenter
                antialiasing: true
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    Core.Icons.drawIcon(ctx, "dialog", width, height, Core.Theme.primary, 1.05)
                }
                Connections {
                    target: Core.Theme
                    function onModeChanged() { dialogIcon.requestPaint() }
                    function onPrimaryChanged() { dialogIcon.requestPaint() }
                }
            }
            Text {
                width: parent.width - dialogIcon.width - parent.spacing
                text: root.dialogTitle
                color: Core.Theme.color.text
                font.pixelSize: Core.Theme.sp(18)
                font.bold: true
                elide: Text.ElideRight
            }
        }

        Column {
            id: body
            width: parent.width
            spacing: 10
        }
    }
}
