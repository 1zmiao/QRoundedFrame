import QtQuick
import "../core" as Core
import "../controls"

Item {
    id: root

    property bool appReady: typeof App !== "undefined" && App !== null
    property var memorySample: ({ "rss": 0, "private": 0 })
    property string updateStatus: ""

    function refreshMemorySample() {
        if (root.visible && root.appReady && App.requestMemorySample)
            App.requestMemorySample()
    }

    function checkUpdate() {
        if (!root.appReady || !App.callWorker) {
            root.updateStatus = "更新检查不可用"
            return
        }
        const response = App.callWorker("check_update", ({}))
        if (!response || !response.ok) {
            root.updateStatus = "更新检查失败：" + String(response && response.error ? response.error : "未知错误")
            return
        }
        const result = response.result || ({})
        root.updateStatus = String(result.message || "当前已是最新版本")
    }

    Component.onCompleted: root.refreshMemorySample()

    Connections {
        target: root.appReady ? App : null
        function onMemorySampleReady(sample) {
            if (root.visible)
                root.memorySample = sample
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.visible
        triggeredOnStart: false
        onTriggered: root.refreshMemorySample()
    }

    DragScrollArea {
        anchors.fill: parent
        spacing: Core.Theme.metrics.spacing

        Rectangle {
            width: parent.width
            height: Math.max(Core.Theme.dp(220), updateContent.implicitHeight + Core.Theme.metrics.cardHeightPadding)
            radius: Core.Theme.radius.card
            color: Core.Theme.color.hero
            border.color: Core.Theme.color.cardOutline
            Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }

            BackgroundRipple { radius: parent.radius }
            CardAccentGlow { radius: parent.radius }

            Column {
                id: updateContent
                z: 1
                anchors.fill: parent
                anchors.margins: Core.Theme.metrics.cardPadding
                spacing: Core.Theme.dp(10)

                Text {
                    text: "更新"
                    color: Core.Theme.color.text
                    font.pixelSize: Core.Theme.sp(24)
                    font.family: Core.Theme.headingFontFamily
                    font.weight: Core.Theme.headingFontWeight
                    font.letterSpacing: Core.Theme.headingLetterSpacing
                }

                Text {
                    width: parent.width
                    text: "这里可以放置更新界面。网络请求和更新逻辑建议放在 Python 中，并通过安全信号暴露给 QML。"
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    wrapMode: Text.WordWrap
                    lineHeight: Core.Theme.bodyLineHeight
                }

                Flow {
                    width: parent.width
                    spacing: Core.Theme.dp(8)
                    AppCheckBox { text: "启用功能 A"; storageKey: "settings/featureA"; checked: true; autoLoad: true }
                    AppCheckBox { text: "启用功能 B"; storageKey: "settings/featureB"; autoLoad: true }
                    AppButton { text: "检查更新"; outlineGhost: true; onClicked: root.checkUpdate() }
                }

                Text {
                    width: parent.width
                    visible: root.updateStatus.length > 0
                    text: root.updateStatus
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.caption
                    wrapMode: Text.WordWrap
                    lineHeight: Core.Theme.bodyLineHeight
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Math.max(Core.Theme.dp(156), memoryContent.implicitHeight + Core.Theme.metrics.cardHeightPadding)
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.cardOutline
            Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }

            BackgroundRipple { radius: parent.radius }
            CardAccentGlow { radius: parent.radius }

            Column {
                id: memoryContent
                z: 1
                anchors.fill: parent
                anchors.margins: Core.Theme.metrics.cardPadding
                spacing: Core.Theme.dp(8)

                Text {
                    text: "运行状态"
                    color: Core.Theme.color.text
                    font.pixelSize: Core.Theme.fontSize.subtitle
                    font.family: Core.Theme.headingFontFamily
                    font.weight: Core.Theme.headingFontWeight
                    font.letterSpacing: Core.Theme.headingLetterSpacing
                }

                Text {
                    width: parent.width
                    text: "当前私有驻留内存：" + Number(root.memorySample["ws_private"] || 0).toFixed(1) + " MB"
                    color: Core.Theme.color.text
                    font.pixelSize: Core.Theme.fontSize.body
                    font.family: Core.Theme.appFontFamily
                }

                Text {
                    width: parent.width
                    text: "这个口径对应 Working Set - Private，更接近用户在任务管理器里关心的当前实际私有内存。"
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.caption
                    font.family: Core.Theme.appFontFamily
                    wrapMode: Text.WordWrap
                    lineHeight: Core.Theme.bodyLineHeight
                }

            }
        }
    }
}
