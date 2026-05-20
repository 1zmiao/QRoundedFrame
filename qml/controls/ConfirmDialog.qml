import QtQuick
import "../controls"
import "../core" as Core

AppDialog {
    id: root
    dialogTitle: "确认"

    property string message: "确定要继续吗？"
    signal confirmed()
    signal canceled()

    Text {
        width: parent.width
        text: root.message
        wrapMode: Text.WordWrap
        color: Core.Theme.color.mutedText
        font.pixelSize: Core.Theme.sp(13)
        lineHeight: 1.25
    }

    Row {
        width: parent.width
        spacing: 8
        layoutDirection: Qt.RightToLeft
        AppButton { text: "确定"; variant: "primary"; minButtonWidth: 84; onClicked: { root.confirmed(); root.close() } }
        AppButton { text: "取消"; variant: "soft"; minButtonWidth: 84; onClicked: { root.canceled(); root.close() } }
    }
}
