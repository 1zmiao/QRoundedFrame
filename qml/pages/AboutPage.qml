import QtQuick
import "../core" as Core
import "../controls"

Item {
    id: root

    DragScrollArea {
        anchors.fill: parent
        spacing: Core.Theme.metrics.spacing

        Rectangle {
            width: parent.width
            height: Math.max(Core.Theme.dp(154), heroContent.implicitHeight + Core.Theme.metrics.cardHeightPadding)
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
                    text: "关于 QRoundedFrame"
                    color: Core.Theme.color.text
                    font.pixelSize: Core.Theme.sp(24)
                    font.family: Core.Theme.headingFontFamily
                    font.weight: Core.Theme.headingFontWeight
                    font.letterSpacing: Core.Theme.headingLetterSpacing
                }
                Text {
                    width: parent.width
                    text: "一个面向桌面工具软件的 C++ Qt Quick/QML 圆角窗口基础框架。界面和 UI 运行时由 C++/QML 负责，Windows 窗口行为由 C++/QWindowKit 与 native bridge 承接，目标是在保持原生拖拽、缩放、贴边手感的同时，提供四角统一圆角和可控阴影。"
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    font.family: Core.Theme.appFontFamily
                    wrapMode: Text.WordWrap
                    lineHeight: Core.Theme.bodyLineHeight
                }
            }
        }

        Rectangle {
            width: parent.width
            height: behaviorContent.implicitHeight + Core.Theme.metrics.cardHeightPadding
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.cardOutline
            Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }

            BackgroundRipple { radius: parent.radius }
            CardAccentGlow { radius: parent.radius }

            Column {
                id: behaviorContent
                z: 1
                anchors.fill: parent
                anchors.margins: Core.Theme.metrics.cardPadding
                spacing: Core.Theme.dp(9)

                Text { text: "窗口策略"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.sp(18); font.family: Core.Theme.headingFontFamily; font.weight: Core.Theme.headingFontWeight; font.letterSpacing: Core.Theme.headingLetterSpacing }
                Text {
                    width: parent.width
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    font.family: Core.Theme.appFontFamily
                    wrapMode: Text.WordWrap
                    lineHeight: Core.Theme.bodyLineHeight
                    text: "Windows 11 优先使用系统圆角与系统阴影；Windows 10、虚拟机、基础显示驱动等圆角不完整环境，会切换到自定义外置阴影与圆角裁剪。主窗口贴边、最大化、复原、拖拽和缩放仍交给系统/native 层处理，避免 QML 手写几何导致窗口漂移。"
                }
                Text {
                    width: parent.width
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    font.family: Core.Theme.appFontFamily
                    wrapMode: Text.WordWrap
                    lineHeight: Core.Theme.bodyLineHeight
                    text: "Linux 不默认硬套 Windows 风格。Wayland、GNOME 或未知桌面环境优先走系统标题栏保守路径；X11 且经过测试的窗口管理器，再考虑启用自定义无边框和阴影策略。"
                }
            }
        }

        Rectangle {
            width: parent.width
            height: advantageContent.implicitHeight + Core.Theme.metrics.cardHeightPadding
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.cardOutline
            Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }

            BackgroundRipple { radius: parent.radius }
            CardAccentGlow { radius: parent.radius }

            Column {
                id: advantageContent
                z: 1
                anchors.fill: parent
                anchors.margins: Core.Theme.metrics.cardPadding
                spacing: Core.Theme.dp(9)

                Text { text: "设计重点"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.sp(18); font.family: Core.Theme.headingFontFamily; font.weight: Core.Theme.headingFontWeight; font.letterSpacing: Core.Theme.headingLetterSpacing }
                Text {
                    width: parent.width
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    font.family: Core.Theme.appFontFamily
                    wrapMode: Text.WordWrap
                    lineHeight: Core.Theme.bodyLineHeight
                    text: "- Windows 无边框拖拽、缩放、贴边和最大化复原尽量接近原生窗口体验。\n- 自定义阴影不再参与真实窗口几何，避免贴边时被阴影边界撑开。\n- 主题、标题栏、侧边栏、菜单、Toast、弹窗和表单控件都按模块复用。\n- 页面按需加载；关闭子窗口后释放页面对象并回收缓存，降低多窗口内存压力。"
                }
            }
        }

        Rectangle {
            width: parent.width
            height: performanceContent.implicitHeight + Core.Theme.metrics.cardHeightPadding
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
                spacing: Core.Theme.dp(9)

                Text { text: "性能与低内存"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.sp(18); font.family: Core.Theme.headingFontFamily; font.weight: Core.Theme.headingFontWeight; font.letterSpacing: Core.Theme.headingLetterSpacing }
                Text {
                    width: parent.width
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    font.family: Core.Theme.appFontFamily
                    wrapMode: Text.WordWrap
                    lineHeight: Core.Theme.bodyLineHeight
                    text: "主窗口保留完整 QML 视觉效果；子窗口支持独立顶层窗口和页内子窗口两条路径。低内存策略会减少关闭后的驻留对象，并允许把轻量内容放到主窗口内部打开，从而减少重复创建完整 QML 顶层窗口的开销。"
                }
            }
        }

        Rectangle {
            width: parent.width
            height: extensionContent.implicitHeight + Core.Theme.metrics.cardHeightPadding
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.cardOutline
            Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }

            BackgroundRipple { radius: parent.radius }
            CardAccentGlow { radius: parent.radius }

            Column {
                id: extensionContent
                z: 1
                anchors.fill: parent
                anchors.margins: Core.Theme.metrics.cardPadding
                spacing: Core.Theme.dp(9)

                Text { text: "扩展入口"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.sp(18); font.family: Core.Theme.headingFontFamily; font.weight: Core.Theme.headingFontWeight; font.letterSpacing: Core.Theme.headingLetterSpacing }
                Text {
                    width: parent.width
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    font.family: Core.Theme.appFontFamily
                    wrapMode: Text.WordWrap
                    lineHeight: Core.Theme.bodyLineHeight
                    text: "业务页面放在 qml/pages；通用控件放在 qml/controls；主题 token 在 qml/core/Theme.qml；C++ UI 运行时在 app/cpp/ui_runtime；Windows native 窗口插件在 app/cpp/frameless_native。普通配置和密文配置已拆分，适合作为桌面工具软件的基础工程。"
                }
            }
        }
    }
}
