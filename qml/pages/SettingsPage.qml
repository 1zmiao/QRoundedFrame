import QtQuick
import QtQuick.Controls
import "../core" as Core
import "../controls"

Item {
    id: root

    property bool appReady: typeof App !== "undefined" && App !== null
    function settingValue(key, fallback) { return appReady && App.settings ? App.settings.valueOr(key, fallback) : fallback }
    function settingsPath() { return appReady && App.settings ? App.settings.path() : "" }
    function trayIconPath() { return appReady && App.tray ? App.tray.iconPath : "resources/icons/tray_icon.png" }
    function trayDefaultIconPath() { return appReady && App.tray ? App.tray.defaultIconPath() : "resources/icons/tray_icon.png" }
    function toastHost() {
        var w = root.Window.window
        if (w && w.showToast)
            return w
        if (typeof NativeHost !== "undefined" && NativeHost && NativeHost.showToast)
            return NativeHost
        return null
    }

    DragScrollArea {
        anchors.fill: parent

        Rectangle {
            width: parent.width
            height: settingsColumn.implicitHeight + Core.Theme.dp(36)
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.outlineAccent
            antialiasing: true
            Behavior on color { ColorAnimation { duration: 150 } }

            BackgroundRipple { radius: parent.radius }

            Column {
                id: settingsColumn
                z: 1
                anchors.fill: parent
                anchors.margins: Core.Theme.dp(18)
                spacing: Core.Theme.dp(12)

                Text { text: "设置"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.fontSize.title; font.bold: true }
                Text { width: parent.width; text: "这些设置会保存在软件根目录下的本地 JSON 配置文件中。"; color: Core.Theme.color.mutedText; font.pixelSize: Core.Theme.fontSize.body; wrapMode: Text.WordWrap }
                Text { width: parent.width; text: root.settingsPath(); color: Core.Theme.color.mutedText; font.pixelSize: Core.Theme.fontSize.caption; elide: Text.ElideRight }

                AppCheckBox { text: "启用功能 A"; storageKey: "settings/featureA"; checked: true; autoLoad: true }
                AppCheckBox { text: "启用功能 B"; storageKey: "settings/featureB"; autoLoad: true }
                AppCheckBox {
                    text: "关闭窗口到托盘图标"
                    checked: root.appReady && App.tray ? App.tray.closeToTray : root.settingValue("window/closeToTray", root.settingValue("window/minimizeToTray", false))
                    onToggled: {
                        if (root.appReady && App.tray)
                            App.tray.setCloseToTray(checked)
                        else if (root.appReady && App.settings)
                            App.settings.setValue("window/closeToTray", checked)
                    }
                }
                AppCheckBox {
                    text: "显示标题栏调色按钮"
                    checked: Core.Theme.showColorButton
                    onClicked: {
                        if (root.appReady && App.theme) App.theme.setShowColorButton(checked)
                        else if (root.appReady && App.settings) App.settings.setValue("ui/showColorButton", checked)
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Core.Theme.color.hairline; opacity: 0.75 }

                Column {
                    width: parent.width
                    spacing: Core.Theme.dp(6)
                    Row {
                        width: parent.width
                        spacing: Core.Theme.dp(8)
                        Text { text: "界面字体大小"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.fontSize.body; width: Core.Theme.dp(120); anchors.verticalCenter: parent.verticalCenter }
                        Text { text: Math.round(13 * Core.Theme.fontScale) + " px / " + Math.round(Core.Theme.fontScale * 100) + "%"; color: Core.Theme.color.mutedText; font.pixelSize: Core.Theme.fontSize.control; width: Core.Theme.dp(94); anchors.verticalCenter: parent.verticalCenter }
                        AppButton { text: "重置"; variant: "soft"; minWidth: Core.Theme.dp(56); horizontalPadding: Core.Theme.dp(12); onClicked: if (root.appReady && App.theme) App.theme.resetFontScale() }
                    }
                    Slider {
                        id: fontSlider
                        width: parent.width
                        from: 85
                        to: 130
                        stepSize: 5
                        snapMode: Slider.SnapAlways
                        value: Math.round(Core.Theme.fontScale * 100 / 5) * 5
                        live: true
                        onMoved: if (root.appReady && App.theme) App.theme.setFontScale(value / 100.0)
                        background: Item {
                            x: fontSlider.leftPadding
                            y: fontSlider.topPadding + fontSlider.availableHeight / 2 - height / 2
                            implicitWidth: Core.Theme.dp(200)
                            implicitHeight: Core.Theme.dp(18)
                            width: fontSlider.availableWidth
                            height: implicitHeight

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: Core.Theme.dp(4)
                                radius: 2
                                color: Core.Theme.primarySoft
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: fontSlider.visualPosition * parent.width
                                height: Core.Theme.dp(4)
                                radius: 2
                                color: Core.Theme.primary
                            }
                            Repeater {
                                model: 10
                                delegate: Rectangle {
                                    width: Core.Theme.dp(2)
                                    height: Core.Theme.dp(index % 2 === 0 ? 10 : 7)
                                    radius: 1
                                    color: Core.Theme.mode === "dark" ? "#A8A3C7" : "#667085"
                                    opacity: 0.75
                                    x: index * (parent.width - width) / 9
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                        handle: Rectangle {
                            x: fontSlider.leftPadding + fontSlider.visualPosition * (fontSlider.availableWidth - width)
                            y: fontSlider.topPadding + fontSlider.availableHeight / 2 - height / 2
                            width: Core.Theme.dp(20)
                            height: Core.Theme.dp(20)
                            radius: width / 2
                            color: Core.Theme.primary
                            border.color: Core.Theme.color.card
                            border.width: 2
                        }
                    }
                    Row {
                        width: parent.width
                        spacing: 0
                        Repeater {
                            model: ["85", "90", "95", "100", "105", "110", "115", "120", "125", "130"]
                            delegate: Text {
                                width: parent.width / 10
                                text: modelData
                                color: Core.Theme.color.mutedText
                                font.pixelSize: Core.Theme.fontSize.caption
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Core.Theme.dp(6)
                    Text { width: parent.width; text: "托盘图标文件：" + root.trayIconPath(); color: Core.Theme.color.mutedText; font.pixelSize: Core.Theme.fontSize.caption; elide: Text.ElideRight }
                    Text { width: parent.width; text: "默认图标位置：" + root.trayDefaultIconPath(); color: Core.Theme.color.mutedText; font.pixelSize: Core.Theme.fontSize.caption; elide: Text.ElideRight }
                    Text { width: parent.width; text: "可以直接替换默认 PNG，也可以在下面输入 PNG/ICO 的绝对路径并保存。"; color: Core.Theme.color.mutedText; font.pixelSize: Core.Theme.fontSize.caption; wrapMode: Text.WordWrap }
                }

                AppTextField { id: trayIconPathInput; width: parent.width; placeholderText: "自定义托盘图标路径，可留空"; storageKey: "tray/iconPath"; autoLoad: true; onSaved: if (root.appReady && App.tray) App.tray.setIconPath(text) }
                AppTextField { id: projectPathInput; width: parent.width; placeholderText: "默认项目路径"; storageKey: "paths/defaultProject"; autoLoad: true }
                Row {
                    spacing: Core.Theme.dp(8)
                    AppButton {
                        variant: "primary"
                        text: "保存设置"
                        onClicked: {
                            if (!root.appReady || !App.settings) return
                            App.settings.setValue("paths/defaultProject", projectPathInput.text)
                            App.settings.setValue("tray/iconPath", trayIconPathInput.text)
                            if (App.tray)
                                App.tray.setIconPath(trayIconPathInput.text)
                            const host = root.toastHost()
                            if (host && host.showToast)
                                host.showToast("设置已保存")
                        }
                    }
                    AppButton {
                        variant: "soft"
                        text: "切换日夜主题"
                        onClicked: {
                            if (!root.appReady || !App.theme) return
                            const next = Core.Theme.mode === "dark" ? "light" : "dark"
                            const host = root.Window.window
                            if (host && host.changeThemeWithRipple)
                                host.changeThemeWithRipple(next, host.width / 2, host.height / 2)
                            else
                                App.theme.setMode(next)
                        }
                    }
                }
            }
        }
    }
}
