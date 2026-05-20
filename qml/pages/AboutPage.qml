import QtQuick
import "../core" as Core
import "../controls"

Item {
    DragScrollArea {
        anchors.fill: parent
        spacing: 14

        Rectangle {
            width: parent.width
            height: 148
            radius: Core.Theme.radius.card
            color: Core.Theme.color.hero
            border.color: Core.Theme.color.outlineAccent

            BackgroundRipple { radius: parent.radius }

            Column {
                z: 1
                anchors.fill: parent
                anchors.margins: 18
                spacing: 8
                Text { text: "关于这个框架"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.sp(24); font.bold: true }
                Text {
                    width: parent.width
                    text: "这是一个面向后续桌面软件复用的 PySide6 + QML 无边框窗口基础模板。主界面、子窗口、标题栏、配置、加密存储、托盘和常用控件都按组件化方式拆分。"
                    color: Core.Theme.color.mutedText
                    wrapMode: Text.WordWrap
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 254
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.outlineAccent

            BackgroundRipple { radius: parent.radius }

            Column {
                z: 1
                anchors.fill: parent
                anchors.margins: 18
                spacing: 9
                Text { text: "窗口行为实现"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.sp(18); font.bold: true }
                Text { width: parent.width; color: Core.Theme.color.mutedText; wrapMode: Text.WordWrap; text: "FramelessWindow.qml 是统一窗口壳层。标题栏只在拖动距离超过阈值后才通知 Python 开始移动，所以单击最大化标题栏不会错误复原窗口。窗口移动由 app/bridge/window_controller.py 统一处理，鼠标释放丢失时还有 16ms 轮询兜底，贴边预览和最终最大化都从同一个控制器发出。" }
                Text { width: parent.width; color: Core.Theme.color.mutedText; wrapMode: Text.WordWrap; text: "当前版本使用原生窗口样式恢复系统级阴影，避免外部 QML 阴影窗口跟不上拖动或抢占层级。Windows 下由 WM_NCHITTEST 处理边缘缩放命中，标题栏拖拽使用 WM_NCLBUTTONDOWN/HTCAPTION 原生路径，最大化/全屏时禁用圆角和边缘缩放，恢复后回到普通窗口状态。" }
            }
        }

        Rectangle {
            width: parent.width
            height: 270
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.outlineAccent

            BackgroundRipple { radius: parent.radius }

            Column {
                z: 1
                anchors.fill: parent
                anchors.margins: 18
                spacing: 9
                Text { text: "界面和性能优化"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.sp(18); font.bold: true }
                Text { width: parent.width; color: Core.Theme.color.mutedText; wrapMode: Text.WordWrap; text: "页面由 qml/layout/PageHost.qml 使用 Loader 懒加载，未切换到的页面不会创建，重页面后续可以继续拆分成内部 Loader 或 C++/Python 模型。导航栏、弹窗、按钮、文本框、右键菜单和标题栏按钮全部是可复用 QML 组件。" }
                Text { width: parent.width; color: Core.Theme.color.mutedText; wrapMode: Text.WordWrap; text: "主题切换由 ThemeTransitionLayer 播放 5 层延迟圆形扩散。窗口、标题栏、侧栏和卡片都把扩散层放在背景与文字之间的底层位置，所以能看到背景涟漪，但不会盖住文字和控件。主题色集中在 core/Theme.qml 中生成 token，图标集中在 core/Icons.qml 中绘制，便于换肤和替换图标体系。" }
            }
        }

        Rectangle {
            width: parent.width
            height: 230
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.outlineAccent

            BackgroundRipple { radius: parent.radius }

            Column {
                z: 1
                anchors.fill: parent
                anchors.margins: 18
                spacing: 9
                Text { text: "存储和扩展接口"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.sp(18); font.bold: true }
                Text { width: parent.width; color: Core.Theme.color.mutedText; wrapMode: Text.WordWrap; text: "普通配置写入软件根目录 user_data/config/settings.json。密文配置写入 user_data/secure/secrets.bin，文件名保持简短，文件内容是加密后的乱码。控件可以直接设置 storageKey；需要加密时继承 SecureTextField 或使用 StorageBinding { encrypted: true }。" }
                Text { width: parent.width; color: Core.Theme.color.mutedText; wrapMode: Text.WordWrap; text: "后续如果需要更强的系统原生能力，可以在 app/native/ 下补 C++ helper，把 Windows DWM、WM_NCHITTEST、Linux X11/Wayland 特殊行为封装成同一组 Python 可调用接口。" }
            }
        }
    }
}
