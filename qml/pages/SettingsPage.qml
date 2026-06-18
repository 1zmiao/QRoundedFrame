import QtQuick
import "../core" as Core
import "../controls"

Item {
    id: root

    property bool deferredControlsReady: true
    property bool appReady: typeof App !== "undefined" && App !== null
    function settingValue(key, fallback) { return appReady && App.settings ? App.settings.valueOr(key, fallback) : fallback }
    function settingsPath() { return appReady && App.settings ? App.settings.path() : "" }
    function trayIconPath() { return appReady && App.tray ? App.tray.iconPath : "resources/app_icon.ico" }
    function trayDefaultIconPath() { return appReady && App.tray ? App.tray.defaultIconPath() : "resources/app_icon.ico" }
    function performanceProfile() { return appReady && App.performance ? App.performance.resourceProfile : "auto" }
    function effectiveProfile() { return appReady && App.performance ? App.performance.effectiveProfile : "normal" }
    function profileIndex(profile) {
        if (profile === "normal") return 1
        if (profile === "low-memory") return 2
        return 0
    }
    function profileFromIndex(index) {
        if (index === 1) return "normal"
        if (index === 2) return "low-memory"
        return "auto"
    }
    function toastHost() {
        var w = root.Window.window
        if (w && w.showToast)
            return w
        if (typeof NativeHost !== "undefined" && NativeHost && NativeHost.showToast)
            return NativeHost
        return null
    }
    function showToast(message) {
        const host = root.toastHost()
        if (host && host.showToast)
            host.showToast(message)
    }
    function commitFontSlider() {
        if (root.appReady && App.theme)
            App.theme.setFontScale(fontSlider.value / 100.0)
    }
    function fontSliderValue() {
        return Math.round(Core.Theme.fontScale * 100 / 5) * 5
    }
    function syncFontSlider() {
        fontSlider.value = root.fontSliderValue()
    }

    DragScrollArea {
        anchors.fill: parent
        spacing: Core.Theme.metrics.spacing

        Rectangle {
            width: parent.width
            height: settingsColumn.implicitHeight + Core.Theme.metrics.cardHeightPadding
            radius: Core.Theme.radius.card
            color: Core.Theme.color.hero
            border.color: Core.Theme.color.cardOutline
            Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            antialiasing: true

            BackgroundRipple { radius: parent.radius }
            CardAccentGlow { radius: parent.radius }

            Column {
                id: settingsColumn
                z: 1
                anchors.fill: parent
                anchors.margins: Core.Theme.metrics.cardPadding
                spacing: Core.Theme.dp(12)

                Text { text: "设置"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.fontSize.title; font.family: Core.Theme.headingFontFamily; font.weight: Core.Theme.headingFontWeight; font.letterSpacing: Core.Theme.headingLetterSpacing }
                Text { width: parent.width; text: "这些设置会保存在软件根目录下的本地 JSON 配置文件中。"; color: Core.Theme.color.mutedText; font.pixelSize: Core.Theme.fontSize.body; wrapMode: Text.WordWrap; lineHeight: Core.Theme.bodyLineHeight }
                Text { width: parent.width; text: root.settingsPath(); color: Core.Theme.color.mutedText; font.pixelSize: Core.Theme.fontSize.caption; elide: Text.ElideRight }

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
                Text { text: "标题栏状态栏"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.fontSize.body; font.family: Core.Theme.headingFontFamily }
                Flow {
                    width: parent.width
                    spacing: Core.Theme.dp(8)
                    AppCheckBox {
                        text: "CPU"
                        storageKey: "ui/showTitleBarCpu"
                        checked: false
                        autoLoad: true
                    }
                    AppCheckBox {
                        text: "内存"
                        storageKey: "ui/showTitleBarMemory"
                        checked: true
                        autoLoad: true
                    }
                    AppCheckBox {
                        text: "GPU"
                        storageKey: "ui/showTitleBarGpu"
                        checked: false
                        autoLoad: true
                    }
                }

                Flow {
                    width: parent.width
                    spacing: Core.Theme.dp(8)
                    AppButton {
                        variant: "primary"
                        text: "保存设置"
                        onClicked: { root.showToast("设置已保存") }
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
                            else if (typeof NativeHost !== "undefined" && NativeHost && NativeHost.changeThemeWithRipple)
                                NativeHost.changeThemeWithRipple(next, root.width / 2, root.height / 2)
                            else
                                App.theme.setMode(next)
                        }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: fontColumn.implicitHeight + Core.Theme.metrics.cardHeightPadding
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.cardOutline
            Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            antialiasing: true

            BackgroundRipple { radius: parent.radius }
            CardAccentGlow { radius: parent.radius }

            Column {
                id: fontColumn
                z: 1
                anchors.fill: parent
                anchors.margins: Core.Theme.metrics.cardPadding
                spacing: Core.Theme.dp(12)

                Text { text: "界面字体"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.fontSize.subtitle; font.family: Core.Theme.headingFontFamily; font.weight: Core.Theme.headingFontWeight; font.letterSpacing: Core.Theme.headingLetterSpacing }

                Column {
                    width: parent.width
                    spacing: Core.Theme.dp(6)
                    Flow {
                        width: parent.width
                        spacing: Core.Theme.dp(8)
                        Text { text: "字体大小（Ctrl+滚轮）"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.fontSize.body; width: Core.Theme.dp(168); height: Core.Theme.metrics.controlHeight; verticalAlignment: Text.AlignVCenter }
                        Text { text: Math.round(13 * Core.Theme.fontScale) + " px / " + Math.round(Core.Theme.fontScale * 100) + "%"; color: Core.Theme.color.mutedText; font.pixelSize: Core.Theme.fontSize.control; width: Core.Theme.dp(94); height: Core.Theme.metrics.controlHeight; verticalAlignment: Text.AlignVCenter }
                        AppButton { text: "重置"; variant: "soft"; minWidth: Core.Theme.dp(56); horizontalPadding: Core.Theme.dp(12); onClicked: if (root.appReady && App.theme) App.theme.resetFontScale() }
                    }
                    AppSlider {
                        id: fontSlider
                        width: parent.width
                        from: 85
                        to: 130
                        stepSize: 5
                        tickCount: 10
                        value: root.fontSliderValue()
                        onMoved: root.commitFontSlider()
                        onCommitted: root.commitFontSlider()
                    }
                    Connections { target: root.appReady && App.theme ? App.theme : null; function onFontScaleChanged() { Qt.callLater(root.syncFontSlider) } }
                    Row {
                        width: parent.width
                        spacing: 0
                        Repeater { model: ["85", "90", "95", "100", "105", "110", "115", "120", "125", "130"]; delegate: Text { width: parent.width / 10; text: modelData; color: Core.Theme.color.mutedText; font.pixelSize: Core.Theme.fontSize.caption; horizontalAlignment: Text.AlignHCenter } }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: memoryColumn.implicitHeight + Core.Theme.metrics.cardHeightPadding
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.cardOutline
            Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            antialiasing: true

            BackgroundRipple { radius: parent.radius }
            CardAccentGlow { radius: parent.radius }

            Column {
                id: memoryColumn
                z: 1
                anchors.fill: parent
                anchors.margins: Core.Theme.metrics.cardPadding
                spacing: Core.Theme.dp(12)

                Text {
                    text: "内存优化管理"
                    color: Core.Theme.color.text
                    font.pixelSize: Core.Theme.fontSize.subtitle
                    font.family: Core.Theme.headingFontFamily
                    font.weight: Core.Theme.headingFontWeight
                    font.letterSpacing: Core.Theme.headingLetterSpacing
                }

                Text {
                    width: parent.width
                    text: "进一步的内存优化需开启开发者选项强制设置。默认密码：code"
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.caption
                    font.family: Core.Theme.appFontFamily
                    wrapMode: Text.WordWrap
                    lineHeight: Core.Theme.bodyLineHeight
                }

                AppCheckBox {
                    width: parent.width
                    wrapText: true
                    text: "独立子窗口启用置顶按钮（每个独立子窗口会额外增加约 3MB 内存占用量）"
                    storageKey: "performance/childWindowTopmostEnabled"
                    checked: false
                    autoLoad: true
                }
            }
        }

        Rectangle {
            width: parent.width
            height: developerColumn.implicitHeight + Core.Theme.metrics.cardHeightPadding
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.cardOutline
            Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            antialiasing: true

            BackgroundRipple { radius: parent.radius }
            CardAccentGlow { radius: parent.radius }

            Column {
                id: developerColumn
                z: 1
                anchors.fill: parent
                anchors.margins: Core.Theme.metrics.cardPadding
                spacing: Core.Theme.dp(12)

                Text { text: "开发者选项"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.fontSize.subtitle; font.family: Core.Theme.headingFontFamily; font.weight: Core.Theme.headingFontWeight; font.letterSpacing: Core.Theme.headingLetterSpacing }

                Text {
                    width: parent.width
                    visible: root.appReady && App.performance && App.performance.developerKeyPresent
                    text: "已检测到本机 developer.key，开发者选项已自动展开。路径：" + (root.appReady && App.performance ? App.performance.developerKeyPath : "")
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.caption
                    font.family: Core.Theme.appFontFamily
                    wrapMode: Text.WrapAnywhere
                }
                Text {
                    width: parent.width
                    visible: root.appReady && App.performance && App.performance.developerUnlocked && !App.performance.developerKeyPresent
                    text: "已通过维护口令开启开发者选项。"
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.caption
                    font.family: Core.Theme.appFontFamily
                    wrapMode: Text.WordWrap
                    lineHeight: Core.Theme.bodyLineHeight
                }

                Loader {
                    id: developerUnlockLoader
                    width: parent.width
                    active: !(root.appReady && App.performance && App.performance.developerUnlocked)
                    visible: active
                    height: item ? item.implicitHeight : 0
                    sourceComponent: Flow {
                        width: developerUnlockLoader.width
                        spacing: Core.Theme.dp(8)

                        function tryUnlockDeveloper() {
                            if (!root.appReady || !App.performance)
                                return
                            if (App.performance.unlockDeveloperMode(developerPasswordInput.text))
                                root.showToast("开发者选项已开启")
                            else
                                root.showToast("口令不正确")
                        }

                        AppTextField {
                            id: developerPasswordInput
                            width: Math.min(Core.Theme.dp(260), Math.max(Core.Theme.dp(150), parent.width - unlockButton.width - Core.Theme.dp(8)))
                            placeholderText: "维护口令"
                            encrypted: true
                            revealed: false
                            autoSave: false
                            onAccepted: parent.tryUnlockDeveloper()
                        }
                        AppButton {
                            id: unlockButton
                            variant: "soft"
                            height: developerPasswordInput.height
                            text: "开启"
                            minButtonWidth: Core.Theme.dp(82)
                            onClicked: parent.tryUnlockDeveloper()
                        }
                    }
                }

                Loader {
                    id: developerOptionsLoader
                    width: parent.width
                    active: root.appReady && App.performance && App.performance.developerUnlocked
                    visible: active
                    sourceComponent: Column {
                        width: developerOptionsLoader.width
                        spacing: Core.Theme.dp(8)

                        Flow {
                            width: parent.width
                            spacing: Core.Theme.dp(10)
                            Text { text: "资源档位"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.fontSize.body; width: Core.Theme.dp(86); height: Core.Theme.metrics.controlHeight; verticalAlignment: Text.AlignVCenter }
                            AppSelect {
                                id: profileCombo
                                width: Math.min(Core.Theme.dp(230), Math.max(Core.Theme.dp(150), parent.width - Core.Theme.dp(96)))
                                model: ["自动", "普通模式", "低内存模拟"]
                                currentIndex: root.profileIndex(root.performanceProfile())
                                onActivated: function(index) {
                                    if (root.appReady && App.performance)
                                        App.performance.setResourceProfile(root.profileFromIndex(index))
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            text: "当前生效：" + (root.effectiveProfile() === "low-memory" ? "低内存" : "普通") + "。自动模式只在 4GB 及以下内存设备上进入低内存策略。"
                            color: Core.Theme.color.mutedText
                            font.pixelSize: Core.Theme.fontSize.caption
                            font.family: Core.Theme.appFontFamily
                            wrapMode: Text.WordWrap
                            lineHeight: Core.Theme.bodyLineHeight
                        }
                        // Text {
                        //     width: parent.width
                        //     text: "切换后需重开子窗口才会完整生效。"
                        //     color: Core.Theme.color.mutedText
                        //     font.pixelSize: Core.Theme.fontSize.caption
                        //     font.family: Core.Theme.appFontFamily
                        //     wrapMode: Text.WordWrap
                        //     lineHeight: Core.Theme.bodyLineHeight
                        // }

                        AppCheckBox {
                            width: parent.width
                            wrapText: true
                            text: "自动清理热缓存（根据4G上下内存档位分别超过 110/160MB 时清理）"
                            storageKey: "performance/autoTrimMemory"
                            checked: true
                            autoLoad: true
                        }

                        Connections {
                            target: root.appReady && App.performance ? App.performance : null
                            function onResourceProfileChanged(profile) { profileCombo.currentIndex = root.profileIndex(profile) }
                        }
                    }
                }
            }
        }
    }
}
