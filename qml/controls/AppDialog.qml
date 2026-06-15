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

    property int overlayMargin: {
        let item = parent
        for (let i = 0; item && i < 8; ++i) {
            if (item["shadowVisualInset"] !== undefined)
                return item["shadowVisualInset"]
            item = item.parent
        }
        const w = parent && parent.Window ? parent.Window.window : null
        if (w && w["shadowVisualInset"] !== undefined)
            return w["shadowVisualInset"]
        if (parent && parent.children) {
            for (let i = 0; i < parent.children.length; ++i) {
                const child = parent.children[i]
                if (child && child.shadowVisualInset !== undefined)
                    return child.shadowVisualInset
            }
        }
        return 0
    }
    property int overlayRadius: {
        let item = parent
        for (let i = 0; item && i < 8; ++i) {
            if (item["cornerRadius"] !== undefined)
                return item["cornerRadius"]
            item = item.parent
        }
        const w = parent && parent.Window ? parent.Window.window : null
        if (w && w["cornerRadius"] !== undefined)
            return w["cornerRadius"]
        if (parent && parent.children) {
            for (let i = 0; i < parent.children.length; ++i) {
                const child = parent.children[i]
                if (child && child.cornerRadius !== undefined)
                    return child.cornerRadius
            }
        }
        return Core.Theme.radius.window
    }

    property string dialogTitle: "弹窗"
    default property alias dialogContent: body.data

    function chromeItem() {
        let item = root.parent
        for (let i = 0; item && i < 8; ++i) {
            if (item["shadowVisualInset"] !== undefined)
                return item
            if (item.children) {
                for (let j = 0; j < item.children.length; ++j) {
                    const child = item.children[j]
                    if (child && child["shadowVisualInset"] !== undefined)
                        return child
                }
            }
            item = item.parent
        }
        return root.parent
    }

    function centerInHost() {
        if (!parent)
            return
        const margin = root.hostInset()
        x = Math.round(margin + Math.max(0, (parent.width - margin * 2 - width) / 2))
        y = Math.round(margin + Math.max(0, (parent.height - margin * 2 - height) / 2))
    }

    function hostInset() {
        const host = root.chromeItem()
        if (host && host["shadowVisualInset"] !== undefined)
            return host["shadowVisualInset"]
        return 0
    }

    function hostOrigin(overlayParent) {
        const host = root.chromeItem()
        if (host && overlayParent && host.mapToItem)
            return host.mapToItem(overlayParent, 0, 0)
        return Qt.point(0, 0)
    }

    function overlayX(overlayParent) {
        const origin = hostOrigin(overlayParent)
        return Math.round(origin.x + hostInset())
    }

    function overlayY(overlayParent) {
        const origin = hostOrigin(overlayParent)
        return Math.round(origin.y + hostInset())
    }

    function overlayWidth() {
        const host = root.chromeItem()
        if (!host)
            return 0
        return Math.max(0, host.width - hostInset() * 2)
    }

    function overlayHeight() {
        const host = root.chromeItem()
        if (!host)
            return 0
        return Math.max(0, host.height - hostInset() * 2)
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
    onClosed: {
        if (typeof App !== "undefined" && App && App.trimMemory)
            Qt.callLater(App.trimMemory)
    }
    onWidthChanged: if (visible) centerInHost()
    onHeightChanged: if (visible) centerInHost()

    Overlay.modal: Item {
        Rectangle {
            x: root.overlayX(parent)
            y: root.overlayY(parent)
            width: root.overlayWidth()
            height: root.overlayHeight()
            color: Core.Theme.mode === "dark" ? "#66000000" : "#33000000"
            radius: root.overlayRadius
            antialiasing: true
        }
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
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
        }
    }

    contentItem: Column {
        spacing: 14
        width: root.width - root.leftPadding - root.rightPadding

        Row {
            width: parent.width
            spacing: 8
            IconImage {
                id: dialogIcon
                width: Core.Theme.dp(18)
                height: Core.Theme.dp(18)
                anchors.verticalCenter: parent.verticalCenter
                iconName: "dialog"
                iconColor: Core.Theme.primary
                strokeWidth: 1.05
            }
            Text {
                width: parent.width - dialogIcon.width - parent.spacing
                text: root.dialogTitle
                color: Core.Theme.color.text
                font.pixelSize: Core.Theme.sp(18)
                font.family: Core.Theme.headingFontFamily
                font.weight: Core.Theme.headingFontWeight
                font.letterSpacing: Core.Theme.headingLetterSpacing
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
