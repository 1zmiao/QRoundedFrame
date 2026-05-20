import QtQuick
import QtQuick.Controls
import "../core" as Core

Item {
    id: root

    property alias text: input.text
    readonly property string selectedText: input.selectedText
    property string placeholderText: ""
    property bool readOnly: false
    property bool selectByMouse: true
    property bool encrypted: false
    property bool revealed: true
    property bool autoLoad: false
    property string storageKey: ""
    property bool autoSave: storageKey.length > 0
    property int echoMode: TextInput.Normal
    property int secureEchoMode: TextInput.Password
    property int inputMethodHints: Qt.ImhNone
    property int padding: Core.Theme.dp(10)
    property color color: Core.Theme.color.text
    property color placeholderTextColor: Core.Theme.color.mutedText
    property color selectionColor: Core.Theme.color.selection
    property color selectedTextColor: Core.Theme.color.selectedText

    property string _lastSavedText: ""
    property bool _dirty: false
    property bool _loading: false
    property string _storageModeKey: storageKey.length > 0 ? ("storageModes/" + storageKey) : ""

    function applyPersistedStorageMode() {
        if (!storageKey || storageKey.length === 0 || typeof App === "undefined" || !App || !App.settings)
            return
        const mode = App.settings.valueOr(root._storageModeKey, root.encrypted ? "encrypted" : "plain")
        root.encrypted = mode === "encrypted"
    }

    signal editingFinished()
    signal accepted()
    signal saved(string key, bool encrypted)

    implicitHeight: Core.Theme.metrics.fieldHeight
    height: implicitHeight
    width: 240

    function toastHost() {
        var w = root.Window.window
        if (w && w.showToast)
            return w
        if (typeof NativeHost !== "undefined" && NativeHost && NativeHost.showToast)
            return NativeHost
        return null
    }

    function saveValue(force, notify) {
        if (!storageKey || storageKey.length === 0 || typeof App === "undefined" || !App)
            return false
        const textValue = input.text
        if (App.settings && root._storageModeKey.length > 0)
            App.settings.setValue(root._storageModeKey, root.encrypted ? "encrypted" : "plain")
        if (!force && !root._dirty && textValue === root._lastSavedText)
            return false
        if (encrypted) {
            if (!App.secrets)
                return false
            App.secrets.put(storageKey, ({ "value": textValue, "savedAt": new Date().toString() }))
        } else {
            if (!App.settings)
                return false
            App.settings.setValue(storageKey, textValue)
        }
        root._lastSavedText = textValue
        root._dirty = false
        root.saved(storageKey, encrypted)
        if (notify !== false) {
            const w = toastHost()
            if (w && w.showToast)
                w.showToast("配置更改 - 已保存")
        }
        return true
    }

    function setEncryptedStorage(enabled) {
        enabled = !!enabled
        if (enabled === root.encrypted)
            return
        const textValue = input.text
        if (enabled) {
            if (App.settings && root._storageModeKey.length > 0)
                App.settings.setValue(root._storageModeKey, "encrypted")
            if (App.settings && App.settings.remove)
                App.settings.remove(storageKey)
            if (App.secrets)
                App.secrets.put(storageKey, ({ "value": textValue, "savedAt": new Date().toString() }))
        } else {
            if (App.settings && root._storageModeKey.length > 0)
                App.settings.setValue(root._storageModeKey, "plain")
            if (App.secrets)
                App.secrets.remove(storageKey)
            if (App.settings)
                App.settings.setValue(storageKey, textValue)
        }
        root.encrypted = enabled
        root._lastSavedText = textValue
        root._dirty = false
        const w = toastHost()
        if (w && w.showToast)
            w.showToast(enabled ? "已切换为密文存储" : "已切换为明文存储")
    }

    function scheduleAutoSave() {
        if (root._loading)
            return
        root._dirty = input.text !== root._lastSavedText
        if (autoSave && storageKey.length > 0 && root._dirty)
            autoSaveTimer.restart()
    }

    function readStoredValue(defaultValue) {
        if (!storageKey || storageKey.length === 0 || typeof App === "undefined" || !App)
            return defaultValue
        if (encrypted) {
            if (!App.secrets)
                return defaultValue
            const data = App.secrets.get(storageKey)
            if (data === null || data === undefined)
                return defaultValue
            if (typeof data === "object" && data.value !== undefined)
                return data.value
            return String(data)
        }
        if (!App.settings)
            return defaultValue
        return App.settings.valueOr(storageKey, defaultValue)
    }

    function loadStoredValue(defaultValue) {
        root._loading = true
        input.text = readStoredValue(defaultValue === undefined ? input.text : defaultValue)
        root._lastSavedText = input.text
        root._dirty = false
        root._loading = false
    }

    function cut() { input.cut() }
    function copy() { input.copy() }
    function paste() { input.paste() }
    function selectAll() { input.selectAll() }
    function clearSelection() { input.deselect() }
    function forceInputFocus() { input.forceActiveFocus() }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Core.Theme.radius.button
        color: input.activeFocus ? Core.Theme.color.fieldFocus : Core.Theme.color.field
        border.color: input.activeFocus ? Core.Theme.color.fieldFocusBorder : Core.Theme.color.outline
        border.width: 1
        Behavior on color { ColorAnimation { duration: 100; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 100; easing.type: Easing.OutCubic } }
    }

    Text {
        id: placeholder
        z: 4
        anchors.left: parent.left
        anchors.leftMargin: root.padding
        anchors.right: trailing.left
        anchors.rightMargin: Core.Theme.dp(8)
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text.length === 0
        text: root.placeholderText
        color: root.placeholderTextColor
        opacity: 1.0
        font.pixelSize: Core.Theme.fontSize.control
        elide: Text.ElideRight
    }

    TextInput {
        id: input
        anchors.left: parent.left
        anchors.leftMargin: root.padding
        anchors.right: trailing.left
        anchors.rightMargin: Core.Theme.dp(8)
        anchors.verticalCenter: parent.verticalCenter
        height: Math.max(Core.Theme.dp(24), implicitHeight)
        color: root.color
        selectedTextColor: root.selectedTextColor
        selectionColor: root.selectionColor
        readOnly: root.readOnly
        selectByMouse: root.selectByMouse
        inputMethodHints: root.inputMethodHints
        echoMode: root.encrypted ? (root.revealed ? TextInput.Normal : root.secureEchoMode) : root.echoMode
        clip: true
        font.pixelSize: Core.Theme.fontSize.control
        verticalAlignment: TextInput.AlignVCenter
        onTextEdited: root.scheduleAutoSave()
        onEditingFinished: { root.editingFinished(); root.scheduleAutoSave() }
        onAccepted: { root.accepted(); root.scheduleAutoSave() }
    }

    Item {
        id: trailing
        anchors.right: parent.right
        anchors.rightMargin: Core.Theme.dp(5)
        anchors.verticalCenter: parent.verticalCenter
        height: Core.Theme.dp(26)
        width: root.encrypted ? Core.Theme.dp(30) : 0
        visible: root.encrypted

        IconButton {
            anchors.centerIn: parent
            width: Core.Theme.dp(26)
            height: Core.Theme.dp(24)
            noBorder: true
            iconName: "lock"
            strokeWidth: 1.0
            tooltip: root.revealed ? "点击锁定隐藏明文" : "点击解锁显示明文"
            onClicked: {
                root.revealed = !root.revealed
                input.forceActiveFocus()
            }
        }
    }

    AppContextMenu {
        id: contextMenu
        parent: root.Window.window ? root.Window.window.contentItem : root
    }

    MouseArea {
        id: rightClickCatcher
        anchors.fill: parent
        z: 9999
        acceptedButtons: Qt.RightButton
        hoverEnabled: false
        preventStealing: true
        propagateComposedEvents: false
        onPressed: function(mouse) {
            mouse.accepted = true
            input.forceActiveFocus()
            const host = contextMenu.parent
            const p = root.mapToItem(host, mouse.x, mouse.y)
            if (contextMenu.visible)
                contextMenu.close()
            contextMenu.openForTextField(root, p.x, p.y)
        }
        onReleased: function(mouse) { mouse.accepted = true }
        onClicked: function(mouse) { mouse.accepted = true }
        onPressAndHold: function(mouse) { mouse.accepted = true }
    }

    Timer {
        id: autoSaveTimer
        interval: 360
        repeat: false
        onTriggered: root.saveValue()
    }

    Component.onCompleted: {
        applyPersistedStorageMode()
        if (autoLoad && storageKey.length > 0)
            loadStoredValue(input.text)
        else
            root._lastSavedText = input.text
    }

    Component.onDestruction: {
        if (autoSave && storageKey.length > 0 && root._dirty)
            saveValue(false)
    }
}
