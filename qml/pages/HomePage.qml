import QtQuick
import "../core" as Core
import "../controls"

Item {
    id: root

    property bool appReady: typeof App !== "undefined" && App !== null
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

    function popupHost() {
        let item = root
        for (let i = 0; item && i < 24; ++i) {
            if (item.objectName === "appFrameRoot")
                return item
            item = item.parent
        }
        return root.Window.window ? root.Window.window.contentItem : root
    }

    Loader {
        id: demoDialogLoader
        active: false
        sourceComponent: ConfirmDialog {
            parent: root.popupHost()
            dialogTitle: "确认操作"
            message: "这是一个跟随主题、圆角和按钮样式的轻量确认弹窗，不单独创建顶层窗口。"
            onConfirmed: storageText.text = "弹窗确认时间：" + new Date().toString()
        }
    }

    function openDemoDialog() {
        demoDialogLoader.active = true
        Qt.callLater(function() {
            if (demoDialogLoader.item)
                demoDialogLoader.item.openCentered(root.popupHost())
        })
    }

    DragScrollArea {
        anchors.fill: parent
        spacing: Core.Theme.metrics.spacing

        Rectangle {
            width: parent.width
            height: Math.max(Core.Theme.dp(164), heroContent.implicitHeight + Core.Theme.metrics.cardHeightPadding)
            radius: Core.Theme.radius.card
            color: Core.Theme.color.hero
            border.color: Core.Theme.color.cardOutline
            Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }

            BackgroundRipple { radius: parent.radius }
            CardAccentGlow { radius: parent.radius }

            Column {
                id: heroContent
                z: 1
                anchors.fill: parent
                anchors.margins: Core.Theme.metrics.cardPadding
                spacing: Core.Theme.dp(8)
                Text {
                    text: "跨平台圆角窗口引擎"
                    color: Core.Theme.color.text
                    font.pixelSize: Core.Theme.sp(24)
                    font.family: Core.Theme.headingFontFamily
                    font.weight: Core.Theme.headingFontWeight
                    font.letterSpacing: Core.Theme.headingLetterSpacing
                }
                Text {
                    width: parent.width
                    text: "C++ Qt Quick/QML 负责界面与运行时，C++/QWindowKit 接管无边框拖拽、缩放、贴边和最大化。Windows 与 Linux 尽量保留原生窗口手感，同时保证四个角统一圆角。"
                    wrapMode: Text.WordWrap
                    lineHeight: Core.Theme.bodyLineHeight
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    font.family: Core.Theme.appFontFamily
                }
                Text {
                    width: parent.width
                    text: "Win11 优先使用系统圆角与阴影；Win10、虚拟机和非完整圆角桌面使用外置自定义阴影，避免阴影像素影响真实窗口尺寸。"
                    wrapMode: Text.WordWrap
                    lineHeight: Core.Theme.bodyLineHeight
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.caption
                    font.family: Core.Theme.appFontFamily
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Math.max(Core.Theme.dp(292), storageContent.implicitHeight + Core.Theme.metrics.cardHeightPadding)
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.cardOutline
            Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }

            BackgroundRipple { radius: parent.radius }
            CardAccentGlow { radius: parent.radius }

            Column {
                id: storageContent
                z: 1
                anchors.fill: parent
                anchors.margins: Core.Theme.metrics.cardPadding
                spacing: Core.Theme.dp(10)
                Text { text: "明文与密文存储"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.sp(18); font.family: Core.Theme.headingFontFamily; font.weight: Core.Theme.headingFontWeight; font.letterSpacing: Core.Theme.headingLetterSpacing }
                Text {
                    id: storageText
                    width: parent.width
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    font.family: Core.Theme.appFontFamily
                    wrapMode: Text.WordWrap
                    lineHeight: Core.Theme.bodyLineHeight
                    text: "普通设置进入 user_data/config/settings.json，加密字段进入 user_data/secure/secrets.bin。输入框会自动保存，统一保存入口保留在设置页。"
                }

                AppTextField {
                    id: settingInput
                    width: parent.width
                    placeholderText: "普通文本"
                    storageKey: "demo/input"
                    autoLoad: true
                }

                SecureTextField {
                    id: secretInput
                    width: parent.width
                    placeholderText: "加密文本"
                    storageKey: "demo/token"
                    text: "Hello World"
                    autoLoad: true
                }

                Row {
                    spacing: Core.Theme.dp(8)
                    AppButton {
                        variant: "primary"
                        text: "显示确认弹窗"
                        minButtonWidth: Core.Theme.dp(128)
                        onClicked: root.openDemoDialog()
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Math.max(Core.Theme.dp(238), performanceContent.implicitHeight + Core.Theme.metrics.cardHeightPadding)
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.cardOutline
            Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }

            BackgroundRipple { radius: parent.radius }
            CardAccentGlow { radius: parent.radius }

            Column {
                id: performanceContent
                z: 1
                anchors.fill: parent
                anchors.margins: Core.Theme.metrics.cardPadding
                spacing: Core.Theme.dp(12)
                Text { text: "面向低内存设备的资源策略"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.sp(18); font.family: Core.Theme.headingFontFamily; font.weight: Core.Theme.headingFontWeight; font.letterSpacing: Core.Theme.headingLetterSpacing }
                Text {
                    width: parent.width
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    wrapMode: Text.WordWrap
                    lineHeight: Core.Theme.bodyLineHeight
                    text: "页面按需加载；低内存模式会减少关闭后的驻留对象，并把子窗口里可选的视觉效果逐步降级。完整窗口行为和阴影策略不会随模式热重建。"
                }
                AppCheckBox { text: "示例开关会保存到普通配置"; storageKey: "demo/switch"; autoLoad: true }
                AppTextField { width: parent.width; placeholderText: "示例输入"; storageKey: "demo/performanceInput"; autoLoad: true }
            }
        }
    }
}
