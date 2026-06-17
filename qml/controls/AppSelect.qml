import QtQuick
import "../core" as Core

Item {
    id: root

    property var model: []
    property int currentIndex: 0
    property int rowHeight: Core.Theme.dp(34)
    property bool hovered: mouseArea.containsMouse
    property bool pressed: mouseArea.pressed
    readonly property string displayText: (currentIndex >= 0 && currentIndex < model.length) ? String(model[currentIndex]) : ""

    signal activated(int index)

    implicitWidth: Core.Theme.dp(180)
    implicitHeight: Core.Theme.metrics.controlHeight
    width: implicitWidth
    height: implicitHeight

    function open() {
        popupLoader.active = true
        Qt.callLater(function() {
            if (popupLoader.item)
                popupLoader.item.open()
        })
    }

    function close() {
        if (popupLoader.item)
            popupLoader.item.close()
    }

    function popupHost() {
        let item = root
        for (let i = 0; item && i < 24; ++i) {
            if (item.objectName === "appFrameRoot")
                return item
            item = item.parent
        }
        return root.Window.window ? root.Window.window.contentItem : root
    }

    Rectangle {
        anchors.fill: parent
        radius: Core.Theme.radius.button
        color: root.pressed ? Core.Theme.color.controlPressed : (root.hovered ? Core.Theme.color.controlHover : Core.Theme.color.field)
        border.color: root.hovered ? Core.Theme.color.fieldFocusBorder : Core.Theme.color.outline
        border.width: 1
        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
        Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: Core.Theme.dp(12)
        anchors.right: indicator.left
        anchors.rightMargin: Core.Theme.dp(8)
        anchors.verticalCenter: parent.verticalCenter
        text: root.displayText
        color: Core.Theme.color.text
        font.pixelSize: Core.Theme.fontSize.control
        font.family: Core.Theme.appFontFamily
        elide: Text.ElideRight
        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }

    Text {
        id: indicator
        anchors.right: parent.right
        anchors.rightMargin: Core.Theme.dp(10)
        anchors.verticalCenter: parent.verticalCenter
        text: "▼"
        color: Core.Theme.color.mutedText
        font.pixelSize: Core.Theme.fontSize.tiny
        font.family: Core.Theme.appFontFamily
        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.open()
    }

    Loader {
        id: popupLoader
        active: false
        sourceComponent: Item {
            id: popup
            parent: root.popupHost()
            visible: false
            z: 10000
            width: parent ? parent.width : root.width
            height: parent ? parent.height : (popupColumn.implicitHeight + Core.Theme.dp(8))

            property int popupX: 0
            property int popupY: 0
            property int popupWidth: root.width
            property int popupHeight: popupColumn.implicitHeight + Core.Theme.dp(8)

            function reposition() {
                if (!parent)
                    return
                const gap = Core.Theme.dp(4)
                popupHeight = Math.min(popupColumn.implicitHeight + Core.Theme.dp(8), Math.max(root.rowHeight, parent.height - gap * 2))
                const below = root.mapToItem(parent, 0, root.height + gap)
                const above = root.mapToItem(parent, 0, -popupHeight - gap)
                const downSpace = parent.height - below.y
                const upSpace = above.y + popupHeight
                popupWidth = root.width
                if (downSpace >= popupHeight || downSpace >= upSpace) {
                    popupY = Math.round(Math.min(below.y, parent.height - popupHeight))
                } else {
                    popupY = Math.round(Math.max(0, above.y))
                }
                popupX = Math.round(Math.max(0, Math.min(below.x, parent.width - popupWidth)))
            }

            function open() {
                reposition()
                visible = true
                forceActiveFocus()
            }

            function close() {
                visible = false
                popupLoader.active = false
            }

            Keys.onEscapePressed: popup.close()

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: popup.close()
            }

            Item {
                id: panel
                x: popup.popupX
                y: popup.popupY
                width: popup.popupWidth
                height: popup.popupHeight
                clip: true

                Rectangle {
                    anchors.fill: parent
                    radius: Core.Theme.radius.popup
                    color: Core.Theme.color.card
                    border.color: Core.Theme.mode === "dark" ? Core.Theme.alpha(Qt.lighter(Core.Theme.primary, 1.65), 0.88) : Core.Theme.color.outlineAccent
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                    Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                }

                Column {
                    id: popupColumn
                    anchors.fill: parent
                    anchors.margins: Core.Theme.dp(4)

                    Repeater {
                        model: root.model
                        delegate: Item {
                            id: option
                            width: popupColumn.width
                            height: root.rowHeight
                            property bool selected: index === root.currentIndex
                            property bool optionHovered: optionMouse.containsMouse

                            Rectangle {
                                anchors.fill: parent
                                radius: Core.Theme.radius.button
                                color: option.selected ? Core.Theme.color.navActive : (option.optionHovered ? Core.Theme.color.controlHover : Core.Theme.alpha(Core.Theme.color.controlHover, 0))
                                Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: Core.Theme.dp(10)
                                anchors.right: parent.right
                                anchors.rightMargin: Core.Theme.dp(10)
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData
                                color: option.selected ? Core.Theme.color.navSelectedText : Core.Theme.color.text
                                font.pixelSize: Core.Theme.fontSize.control
                                font.family: Core.Theme.appFontFamily
                                elide: Text.ElideRight
                                Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                            }

                            MouseArea {
                                id: optionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    root.currentIndex = index
                                    root.activated(index)
                                    popup.close()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
