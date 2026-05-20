import QtQuick
import QtQuick.Controls
import "../core" as Core

Popup {
    id: root
    width: 304
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    enter: Transition {}
    exit: Transition {}
    padding: 14

    property real hue: 0.72
    property real saturation: 0.60
    property real valueBrightness: 0.92
    property int wheelSize: 198
    property string currentHex: colorToHex(hsvToRgb(hue, saturation, valueBrightness))
    property string originalHex: currentHex
    property bool copied: false
    property bool _copying: false
    property double _closedAt: 0
    property bool _suppressCloseStamp: false

    signal colorSelected(string colorValue)

    onClosed: { if (!root._suppressCloseStamp) root._closedAt = Date.now(); root._suppressCloseStamp = false }

    background: Item {
        PanelShadow { anchors.fill: panel; radius: Core.Theme.radius.popup }
        Rectangle {
            id: panel
            anchors.fill: parent
            radius: Core.Theme.radius.popup
            color: Core.Theme.color.card
            border.color: Core.Theme.color.outlineAccent
            border.width: 1
        }
    }

    contentItem: Column {
        spacing: 12
        width: root.width - root.leftPadding - root.rightPadding

        Text {
            width: parent.width
            text: "主题色"
            color: Core.Theme.color.text
            font.pixelSize: Core.Theme.sp(14)
            font.bold: true
        }

        Text {
            width: parent.width
            text: "拖动色轮实时预览主题色；色值可复制，取消可恢复打开面板前的颜色。"
            color: Core.Theme.color.mutedText
            wrapMode: Text.WordWrap
            font.pixelSize: Core.Theme.sp(12)
        }

        Item {
            id: wheelBox
            width: root.wheelSize
            height: root.wheelSize
            anchors.horizontalCenter: parent.horizontalCenter

            Image {
                anchors.fill: parent
                source: "../assets/color_wheel.png"
                smooth: true
                mipmap: true
                cache: true
            }


            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 2
                height: parent.height - 2
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: "#88FFFFFF"
            }

            Rectangle {
                width: 18
                height: 18
                radius: 9
                border.width: 2
                border.color: "white"
                color: "transparent"
                x: wheelBox.width / 2 + Math.cos(root.hue * Math.PI * 2) * root.saturation * (wheelBox.width / 2 - 3) - width / 2
                y: wheelBox.height / 2 + Math.sin(root.hue * Math.PI * 2) * root.saturation * (wheelBox.height / 2 - 3) - height / 2

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -3
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Core.Theme.mode === "dark" ? "#CC000000" : "#66000000"
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.CrossCursor
                onPressed: function(mouse) { root.pick(mouse.x, mouse.y) }
                onPositionChanged: function(mouse) {
                    if (pressed)
                        root.pick(mouse.x, mouse.y)
                }
            }
        }

        Text {
            width: parent.width
            text: "亮度"
            color: Core.Theme.color.mutedText
            font.pixelSize: Core.Theme.sp(12)
        }

        Slider {
            id: valueSlider
            width: parent.width
            from: 0.35
            to: 1.0
            value: root.valueBrightness
            onMoved: {
                root.valueBrightness = value
                root.applyColor()
            }
        }

        Row {
            width: parent.width
            spacing: 8

            Rectangle {
                id: colorCopyCard
                width: 56
                height: 30
                radius: Core.Theme.radius.button
                color: root.currentHex
                border.color: Core.Theme.color.outline
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: root.copied ? "✓" : "复制"
                    color: Core.Theme.primaryText
                    font.pixelSize: Core.Theme.sp(root.copied ? 15 : 12)
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true
                    propagateComposedEvents: false
                    cursorShape: Qt.PointingHandCursor
                    onPressed: function(mouse) { mouse.accepted = true }
                    onReleased: function(mouse) { mouse.accepted = true }
                    onClicked: function(mouse) {
                        mouse.accepted = true
                        const copiedHex = String(root.currentHex)
                        if (App.theme.copyText(copiedHex)) {
                            root.copied = true
                            copyReset.restart()
                        }
                    }
                }
            }

            Rectangle {
                id: hexEditBox
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - colorCopyCard.width - 8 - cancelButton.width - 8
                height: 30
                radius: Core.Theme.radius.button
                color: hexInput.activeFocus ? Core.Theme.color.fieldFocus : Core.Theme.color.field
                border.color: hexInput.activeFocus ? Core.Theme.color.fieldFocusBorder : Core.Theme.color.outline
                border.width: 1

                TextInput {
                    id: hexInput
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    height: implicitHeight
                    text: root.currentHex
                    color: Core.Theme.color.text
                    selectionColor: Core.Theme.color.selection
                    selectedTextColor: Core.Theme.primaryText
                    font.pixelSize: Core.Theme.sp(13)
                    selectByMouse: true
                    maximumLength: 7
                    inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhPreferUppercase
                    onTextEdited: root.applyHexText(text, true)
                    onAccepted: root.applyHexText(text, false)
                    onEditingFinished: {
                        if (!/^#[0-9A-F]{6}$/.test(text.toUpperCase()))
                            text = root.currentHex
                    }

                    Connections {
                        target: root
                        function onCurrentHexChanged() {
                            if (!hexInput.activeFocus)
                                hexInput.text = root.currentHex
                        }
                    }
                }
            }

            AppButton {
                id: cancelButton
                minButtonWidth: 50
                text: "取消"
                variant: "soft"
                onClicked: {
                    App.theme.setPrimaryColor(root.originalHex)
                    root.currentHex = root.originalHex
                    hexInput.text = root.originalHex
                    root.close()
                }
            }
        }

    }

    Timer {
        id: copyReset
        interval: 1200
        repeat: false
        onTriggered: {
            root.copied = false
            root._copying = false
        }
    }

    function applyHexText(textValue, keepFocus) {
        if (root._copying)
            return false
        let value = String(textValue || "").trim().toUpperCase()
        if (value.length === 6 && value.charAt(0) !== "#")
            value = "#" + value
        if (!/^#[0-9A-F]{6}$/.test(value)) {
            if (!keepFocus)
                hexInput.text = root.currentHex
            return false
        }
        if (hexInput && hexInput.text !== value)
            hexInput.text = value
        root.currentHex = value
        setFromColor(value)
        root.currentHex = value
        App.theme.setPrimaryColor(value)
        root.colorSelected(value)
        root.copied = false
        return true
    }

    function pick(px, py) {
        const cx = wheelSize / 2
        const cy = wheelSize / 2
        const radius = wheelSize / 2 - 3
        const dx = px - cx
        const dy = py - cy
        const d = Math.sqrt(dx * dx + dy * dy)
        if (d > radius)
            return
        let hval = Math.atan2(dy, dx) / (Math.PI * 2)
        if (hval < 0)
            hval += 1
        root.hue = hval
        root.saturation = Math.max(0, Math.min(1, d / radius))
        applyColor()
    }

    function applyColor() {
        root.currentHex = colorToHex(hsvToRgb(root.hue, root.saturation, root.valueBrightness))
        root.copied = false
        App.theme.setPrimaryColor(root.currentHex)
        root.colorSelected(root.currentHex)
    }

    function setFromColor(c) {
        const rgb = colorInputToRgb(c)
        const hsv = rgbToHsv(rgb.r, rgb.g, rgb.b)
        root.hue = hsv.h
        root.saturation = hsv.s
        root.valueBrightness = Math.max(0.35, hsv.v)
        root.currentHex = colorToHex(hsvToRgb(root.hue, root.saturation, root.valueBrightness))
        valueSlider.value = root.valueBrightness
    }

    function colorInputToRgb(c) {
        if (typeof c === "string") {
            let value = c.trim().toUpperCase()
            if (value.length === 6 && value.charAt(0) !== "#")
                value = "#" + value
            if (/^#[0-9A-F]{6}$/.test(value)) {
                return {
                    "r": parseInt(value.slice(1, 3), 16) / 255.0,
                    "g": parseInt(value.slice(3, 5), 16) / 255.0,
                    "b": parseInt(value.slice(5, 7), 16) / 255.0
                }
            }
        }
        return { "r": c.r, "g": c.g, "b": c.b }
    }

    function hsvToRgb(h, s, v) {
        let r = 0, g = 0, b = 0
        const i = Math.floor(h * 6)
        const f = h * 6 - i
        const p = v * (1 - s)
        const q = v * (1 - f * s)
        const t = v * (1 - (1 - f) * s)
        switch (i % 6) {
        case 0: r = v; g = t; b = p; break
        case 1: r = q; g = v; b = p; break
        case 2: r = p; g = v; b = t; break
        case 3: r = p; g = q; b = v; break
        case 4: r = t; g = p; b = q; break
        case 5: r = v; g = p; b = q; break
        }
        return { "r": Math.round(r * 255), "g": Math.round(g * 255), "b": Math.round(b * 255) }
    }

    function rgbToHsv(r, g, b) {
        const max = Math.max(r, g, b)
        const min = Math.min(r, g, b)
        const d = max - min
        let h = 0
        const s = max === 0 ? 0 : d / max
        const v = max
        if (d !== 0) {
            if (max === r)
                h = ((g - b) / d + (g < b ? 6 : 0)) / 6
            else if (max === g)
                h = ((b - r) / d + 2) / 6
            else
                h = ((r - g) / d + 4) / 6
        }
        return { "h": h, "s": s, "v": v }
    }

    function colorToHex(rgb) {
        function part(v) {
            const s = Math.max(0, Math.min(255, Math.round(v))).toString(16).toUpperCase()
            return s.length === 1 ? "0" + s : s
        }
        return "#" + part(rgb.r) + part(rgb.g) + part(rgb.b)
    }

    function qtColorToHex(c) {
        return colorToHex({ "r": c.r * 255, "g": c.g * 255, "b": c.b * 255 })
    }

    function openNear(item) {
        if (visible) {
            close()
            return
        }
        if (Date.now() - root._closedAt < 220)
            return
        setFromColor(Core.Theme.primary)
        root.originalHex = root.currentHex
        root.copied = false
        const host = root.parent
        const p = item.mapToItem(host, item.width - root.width, item.height + 8)
        const maxX = host ? Math.max(8, host.width - root.width - 10) : p.x
        const maxY = host ? Math.max(8, host.height - root.height - 10) : p.y
        x = Math.max(8, Math.min(maxX, p.x))
        y = Math.max(8, Math.min(maxY, p.y))
        open()
    }

    function toggleNear(item) {
        if (root.visible) {
            root.close()
            return
        }
        openNear(item)
    }
}
