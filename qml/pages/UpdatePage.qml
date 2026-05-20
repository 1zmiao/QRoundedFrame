import QtQuick
import "../core" as Core
import "../controls"

Item {
    DragScrollArea {
        anchors.fill: parent

        Rectangle {
            width: parent.width
            height: 220
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.outlineAccent

            BackgroundRipple { radius: parent.radius }

            Column {
                z: 1
                anchors.fill: parent
                anchors.margins: 18
                spacing: 10
                Text { text: "更新"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.sp(24); font.bold: true }
                Text { width: parent.width; text: "这里可以放置更新界面。网络请求和更新逻辑建议放在 Python 中，并通过安全信号暴露给 QML。"; color: Core.Theme.color.mutedText; wrapMode: Text.WordWrap }
                AppButton { text: "检查更新占位按钮" }
            }
        }
    }
}
