import QtQuick
import QtQuick.Controls
import "../core" as Core

CheckBox {
    id: root

    property string storageKey: ""
    property bool autoLoad: false
    property bool autoSave: storageKey.length > 0
    property bool _loading: false

    function toastHost() {
        var w = root.Window.window
        if (w && w.showToast)
            return w
        if (typeof NativeHost !== "undefined" && NativeHost && NativeHost.showToast)
            return NativeHost
        return null
    }

    spacing: Math.max(7, Math.round(Core.Theme.fontSize.control * 0.60))
    implicitHeight: Math.max(Core.Theme.metrics.controlHeight, indicator.implicitHeight + 6)

    function saveValue() {
        if (!autoSave || storageKey.length === 0 || typeof App === "undefined" || !App || !App.settings)
            return false
        App.settings.setValue(storageKey, checked)
        const w = toastHost()
        if (w && w.showToast)
            w.showToast("配置更改 - 已保存")
        return true
    }

    indicator: Rectangle {
        implicitWidth: Math.max(18, Math.round(Core.Theme.fontSize.control * 1.55))
        implicitHeight: implicitWidth
        x: root.leftPadding
        y: parent.height / 2 - height / 2
        radius: Math.max(4, Math.round(width * 0.25))
        color: root.checked ? Core.Theme.primary : Core.Theme.primarySoft
        border.color: root.checked ? Core.Theme.primary : Core.Theme.color.outlineAccent
        border.width: 1
        Behavior on color { ColorAnimation { duration: 95; easing.type: Easing.OutCubic } }

        Text {
            anchors.centerIn: parent
            text: root.checked ? "✓" : ""
            color: "white"
            font.bold: true
            font.pixelSize: Core.Theme.fontSize.small
        }
    }

    contentItem: Text {
        text: root.text
        color: Core.Theme.color.text
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: Core.Theme.fontSize.control
        leftPadding: root.indicator.width + root.spacing
        elide: Text.ElideRight
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    onToggled: if (!_loading) saveValue()

    Component.onCompleted: {
        if (autoLoad && storageKey.length > 0 && typeof App !== "undefined" && App && App.settings) {
            _loading = true
            checked = App.settings.valueOr(storageKey, checked)
            _loading = false
        }
    }
}
