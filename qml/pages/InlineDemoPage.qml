import QtQuick
import "../core" as Core
import "../controls"

Item {
    DragScrollArea {
        anchors.fill: parent
        spacing: Core.Theme.metrics.spacing

        Rectangle {
            width: parent.width
            height: Math.max(Core.Theme.dp(220), content.implicitHeight + Core.Theme.metrics.cardHeightPadding)
            radius: Core.Theme.radius.card
            color: Core.Theme.color.hero
            border.color: Core.Theme.color.cardOutline
            Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            antialiasing: true

            BackgroundRipple { radius: parent.radius }
            CardAccentGlow { radius: parent.radius }

            Column {
                id: content
                anchors.fill: parent
                anchors.margins: Core.Theme.metrics.cardPadding
                spacing: Core.Theme.dp(10)

                Text {
                    text: "页内子窗口"
                    color: Core.Theme.color.text
                    font.pixelSize: Core.Theme.fontSize.title
                    font.family: Core.Theme.headingFontFamily
                    font.weight: Core.Theme.headingFontWeight
                    font.letterSpacing: Core.Theme.headingLetterSpacing
                }

                Text {
                    width: parent.width
                    text: "这个窗口运行在主窗口内部，不创建新的系统顶层窗口。它适合工具面板、临时表单、局部预览和低内存模式下的轻量页面。"
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    wrapMode: Text.WordWrap
                    lineHeight: Core.Theme.bodyLineHeight
                }

                Text {
                    width: parent.width
                    text: "支持拖拽、边角缩放、关闭和最小化。最小化后会停靠到主窗口左下角，再点击即可恢复。"
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    wrapMode: Text.WordWrap
                    lineHeight: Core.Theme.bodyLineHeight
                }

                Flow {
                    width: parent.width
                    spacing: Core.Theme.dp(8)
                    AppButton {
                        text: "打开关于页内窗"
                        variant: "soft"
                        onPressStarted: App.prepareOpenChild("about", "inline")
                        onClicked: App.requestOpenChild("about", "inline", ({}))
                    }
                    AppButton {
                        text: "打开独立关于窗"
                        variant: "soft"
                        onPressStarted: App.prepareOpenChild("about", "native")
                        onClicked: App.requestOpenChild("about", "native", ({}))
                    }
                }
            }
        }
    }
}
