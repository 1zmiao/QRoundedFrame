import QtQuick
import "../core" as Core
import "../controls"

Item {
    id: root

    readonly property int cardPadding: Core.Theme.dp(18)

    DragScrollArea {
        anchors.fill: parent
        spacing: 14

        Rectangle {
            width: parent.width
            height: Math.max(Core.Theme.dp(142), heroContent.implicitHeight + root.cardPadding * 2)
            radius: Core.Theme.radius.card
            color: Core.Theme.color.hero
            border.color: Core.Theme.color.outlineAccent

            BackgroundRipple { radius: parent.radius }

            Column {
                id: heroContent
                z: 1
                anchors.fill: parent
                anchors.margins: root.cardPadding
                spacing: 8

                Text {
                    text: "关于这个框架"
                    color: Core.Theme.color.text
                    font.pixelSize: Core.Theme.sp(24)
                    font.bold: true
                }
                Text {
                    width: parent.width
                    text: "一个面向后续桌面软件复用的 PySide6 + QML 无边框窗口模板。窗口壳、页面、主题、配置、密文存储、托盘和控件都按模块拆分，可以直接作为新项目的基础工程。"
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    wrapMode: Text.WordWrap
                }
            }
        }

        Rectangle {
            width: parent.width
            height: behaviorContent.implicitHeight + root.cardPadding * 2
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.outlineAccent

            BackgroundRipple { radius: parent.radius }

            Column {
                id: behaviorContent
                z: 1
                anchors.fill: parent
                anchors.margins: root.cardPadding
                spacing: 9

                Text { text: "窗口行为"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.sp(18); font.bold: true }
                Text {
                    width: parent.width
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    wrapMode: Text.WordWrap
                    text: "Windows 主窗口由 app/windows_host.py 使用 QWidget + QQuickWidget 承载 QML 内容，子窗口由 app/bridge/window_controller.py 安装原生事件过滤器；标题栏拖拽和边缘缩放都通过 WM_NCHITTEST 交给系统处理。Linux 继续使用 QML Window 路径，保留原有平台拖拽和缩放逻辑。"
                }
                Text {
                    width: parent.width
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    wrapMode: Text.WordWrap
                    text: "最大化、双击标题栏、顶部贴边、左右贴边之后再拖拽标题栏，Windows 会走原生 HTCAPTION 行为复原并跟随鼠标移动，因此半透明贴边预览、Aero Snap 和 Snap Assist 都由系统触发；QML 贴边预览保留给 Linux 和原生链路不可用时的兜底路径。"
                }
            }
        }

        Rectangle {
            width: parent.width
            height: advantageContent.implicitHeight + root.cardPadding * 2
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.outlineAccent

            BackgroundRipple { radius: parent.radius }

            Column {
                id: advantageContent
                z: 1
                anchors.fill: parent
                anchors.margins: root.cardPadding
                spacing: 9

                Text { text: "软件优点"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.sp(18); font.bold: true }
                Text {
                    width: parent.width
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    wrapMode: Text.WordWrap
                    text: "• Windows 无边框拖拽、缩放、贴边和最大化复原接近原生窗口体验。\n• QML 负责界面渲染，Python 负责窗口、配置、托盘和服务桥接。\n• 页面使用 Loader 懒加载，未访问页面不会提前创建。\n• 主题 token、图标、标题栏、侧栏、菜单、Toast、弹窗和表单控件都可复用。\n• 普通配置和密文配置分离，适合工具类软件保存偏好和敏感字段。"
                }
            }
        }

        Rectangle {
            width: parent.width
            height: interfaceContent.implicitHeight + root.cardPadding * 2
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.outlineAccent

            BackgroundRipple { radius: parent.radius }

            Column {
                id: interfaceContent
                z: 1
                anchors.fill: parent
                anchors.margins: root.cardPadding
                spacing: 9

                Text { text: "可复用接口"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.sp(18); font.bold: true }
                Text {
                    width: parent.width
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    wrapMode: Text.WordWrap
                    text: "App.settings 提供 valueOr、setValue、remove；App.secrets 提供加密版 setValue、value、remove；App.theme 提供 setMode、toggleMode、setPrimaryColor、setFontScale、setShowColorButton。"
                }
                Text {
                    width: parent.width
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    wrapMode: Text.WordWrap
                    text: "App.window 负责子窗口 restoreWindowState、saveWindowState、toggleMaximized、beginMove、updateMove、endMove、beginResize、endResize；App.dialogs.openChild 可打开独立页面子窗口；App.tray 负责最小化到托盘、居中恢复和退出。"
                }
                Text {
                    width: parent.width
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    wrapMode: Text.WordWrap
                    text: "Windows 主窗口使用 NativeHost.toggleMaximized、setAlwaysOnTop、showToast、changeThemeWithRipple、setTitleBarHitTestMetrics；beginSystemMove、updateSystemMove、endSystemMove 保留为非原生链路兜底。普通输入框可直接设置 storageKey；敏感输入使用 SecureTextField 或 StorageBinding { encrypted: true }。"
                }
            }
        }

        Rectangle {
            width: parent.width
            height: extensionContent.implicitHeight + root.cardPadding * 2
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.outlineAccent

            BackgroundRipple { radius: parent.radius }

            Column {
                id: extensionContent
                z: 1
                anchors.fill: parent
                anchors.margins: root.cardPadding
                spacing: 9

                Text { text: "扩展入口"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.sp(18); font.bold: true }
                Text {
                    width: parent.width
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    wrapMode: Text.WordWrap
                    text: "改窗口行为优先看 app/windows_host.py、app/bridge/window_controller.py 和 qml/window/；改界面控件看 qml/controls/；改主题看 qml/core/Theme.qml；改图标看 qml/core/Icons.qml；新增业务页面放到 qml/pages/ 并在 PageHost 中注册。"
                }
            }
        }
    }
}
