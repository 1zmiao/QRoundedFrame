import QtQuick
import "../core" as Core
import "../controls"

Item {
    id: root

    property bool appReady: typeof App !== "undefined" && App !== null
    function settingValue(key, fallback) { return appReady && App.settings ? App.settings.valueOr(key, fallback) : fallback }
    function configPath() { return appReady && App.settings ? App.settings.path() : "" }
    function secretFile() { return appReady && App.secrets ? App.secrets.vaultFile : "" }
    function toastHost() {
        var w = root.Window.window
        if (w && w.showToast)
            return w
        if (typeof NativeHost !== "undefined" && NativeHost && NativeHost.showToast)
            return NativeHost
        return null
    }

    ConfirmDialog {
        id: demoDialog
        parent: root.Window.window ? root.Window.window.contentItem : root
        dialogTitle: "确认操作"
        message: "这是一个普通确认弹窗，不继承无边框窗口行为。它使用与主界面一致的主题、圆角、按钮和文字颜色。"
        onConfirmed: storageText.text = "弹窗确认时间：" + new Date().toString()
    }

    DragScrollArea {
        anchors.fill: parent
        spacing: 16

        Rectangle {
            width: parent.width
            height: 156
            radius: Core.Theme.radius.card
            color: Core.Theme.color.hero
            border.color: Core.Theme.color.outlineAccent
            Behavior on color { ColorAnimation { duration: 150 } }

            BackgroundRipple { radius: parent.radius }

            Column {
                z: 1
                anchors.fill: parent
                anchors.margins: 18
                spacing: 8
                Text { text: "无边框窗口模板"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.sp(24); font.bold: true }
                Text { width: parent.width; text: "这个基础模板演示可复用 QML 窗口、标题栏、页面懒加载、主题切换、普通配置和加密配置接口。"; wrapMode: Text.WordWrap; color: Core.Theme.color.mutedText; font.pixelSize: Core.Theme.fontSize.body }
                Text { text: "明文配置文件：" + root.configPath(); color: Core.Theme.color.mutedText; font.pixelSize: Core.Theme.sp(12); elide: Text.ElideRight; width: parent.width }
                Text { text: "密文配置文件：" + root.secretFile(); color: Core.Theme.color.mutedText; font.pixelSize: Core.Theme.sp(12); elide: Text.ElideRight; width: parent.width }
            }
        }

        Rectangle {
            width: parent.width
            height: 292
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.outlineAccent
            Behavior on color { ColorAnimation { duration: 150 } }

            BackgroundRipple { radius: parent.radius }

            Column {
                z: 1
                anchors.fill: parent
                anchors.margins: 18
                spacing: 10
                Text { text: "存储接口演示"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.sp(18); font.bold: true }
                Text { id: storageText; width: parent.width; color: Core.Theme.color.mutedText; font.pixelSize: Core.Theme.fontSize.body; wrapMode: Text.WordWrap; text: "同一个保存按钮会同时保存普通字段和加密字段。普通字段进入 user_data/config/settings.json，加密字段进入 user_data/secure/secrets.bin。" }

                AppTextField {
                    id: settingInput
                    width: parent.width
                    placeholderText: "普通设置文本"
                    storageKey: "demo/input"
                    autoLoad: true
                }

                SecureTextField {
                    id: secretInput
                    width: parent.width
                    placeholderText: "需要加密保存的文本"
                    storageKey: "demo/token"
                    text: "abc123"
                    autoLoad: true
                }

                Row {
                    spacing: 8
                    AppButton {
                        variant: "primary"
                        text: "保存全部设置"
                        minButtonWidth: 146
                        onClicked: {
                            if (!root.appReady) return
                            settingInput.saveValue(true, false)
                            secretInput.saveValue(true, false)
                            const tokenValue = secretInput.readStoredValue("")
                            const settingKind = settingInput.encrypted ? "密文字段：" : "普通字段："
                            const secretKind = secretInput.encrypted ? "密文字段：" : "普通字段："
                            const w = root.toastHost()
                            if (w && w.showToast) w.showToast("配置更改 - 已保存")
                            storageText.text = "已保存。" + settingKind + settingInput.text
                                    + "\n" + secretKind + tokenValue
                                    + "\n明文配置：" + root.configPath()
                                    + "\n密文配置：" + root.secretFile()
                        }
                    }
                    AppButton {
                        variant: "soft"
                        text: "显示确认弹窗"
                        minButtonWidth: 112
                        onClicked: demoDialog.openCentered(root.Window.window ? root.Window.window.contentItem : root)
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 260
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.outlineAccent
            Behavior on color { ColorAnimation { duration: 150 } }

            BackgroundRipple { radius: parent.radius }

            Column {
                z: 1
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12
                Text { text: "性能模式"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.sp(18); font.bold: true }
                Text { width: parent.width; color: Core.Theme.color.mutedText; font.pixelSize: Core.Theme.fontSize.body; wrapMode: Text.WordWrap; text: "页面由 qml/layout/PageHost.qml 通过 Loader 懒加载，未切换到的页面不会创建。重型页面后续可以继续拆分内部 Loader，或使用 C++/Python 模型暴露给 QML。" }
                AppCheckBox { text: "示例开关会保存到普通配置"; storageKey: "demo/switch"; autoLoad: true }
                AppTextField { width: parent.width; placeholderText: "示例输入"; storageKey: "demo/performanceInput"; autoLoad: true }
            }
        }
    }
}
