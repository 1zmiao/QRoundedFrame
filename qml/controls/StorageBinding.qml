import QtQuick

Item {
    id: root

    property var target: null
    property string storageKey: ""
    property bool encrypted: false
    property bool autoLoad: false
    property bool autoSave: false
    property int autoSaveDelay: 360
    property string valueProperty: "text"

    function toastHost() {
        var w = (target && target.Window && target.Window.window) ? target.Window.window : null
        if (w && w.showToast)
            return w
        if (typeof NativeHost !== "undefined" && NativeHost && NativeHost.showToast)
            return NativeHost
        return null
    }

    function _targetValue(defaultValue) {
        if (!target)
            return defaultValue
        const v = target[valueProperty]
        return v === undefined || v === null ? defaultValue : v
    }

    function notifySaved() {
        var w = toastHost()
        if (w && w.showToast)
            w.showToast("配置更改 - 已保存")
    }

    function saveValue() {
        if (!target || !storageKey || storageKey.length === 0 || typeof App === "undefined" || !App)
            return false
        const v = _targetValue("")
        if (encrypted) {
            if (!App.secrets)
                return false
            App.secrets.put(storageKey, ({ "value": v, "savedAt": new Date().toString() }))
        } else {
            if (!App.settings)
                return false
            App.settings.setValue(storageKey, v)
        }
        notifySaved()
        return true
    }

    function scheduleSave() {
        if (autoSave && storageKey.length > 0)
            timer.restart()
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
        if (!target)
            return
        target[valueProperty] = readStoredValue(defaultValue === undefined ? _targetValue("") : defaultValue)
    }

    Connections {
        target: root.target
        ignoreUnknownSignals: true
        function onTextChanged() { root.scheduleSave() }
        function onCheckedChanged() { root.scheduleSave() }
        function onValueChanged() { root.scheduleSave() }
    }

    Timer {
        id: timer
        interval: root.autoSaveDelay
        repeat: false
        onTriggered: root.saveValue()
    }

    Component.onCompleted: {
        if (autoLoad)
            loadStoredValue(_targetValue(""))
    }

    Component.onDestruction: {
        if (autoSave)
            saveValue()
    }
}
