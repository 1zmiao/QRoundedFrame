pragma Singleton
import QtQuick

QtObject {
    id: theme

    property string mode: (typeof App !== "undefined" && App && App.theme) ? App.theme.mode : "light"
    property color primary: (typeof App !== "undefined" && App && App.theme) ? App.theme.primaryColor : "#537FCD"
    property real fontScale: (typeof App !== "undefined" && App && App.theme) ? App.theme.fontScale : 1.0
    property int settingsRevision: (typeof App !== "undefined" && App && App.settings) ? App.settings.revision : 0
    property int baseFontSize: Math.max(11, Math.min(20, Math.round(13 * fontScale)))
    property real controlScale: Math.max(0.90, Math.min(1.24, fontScale))
    property bool showColorButton: (typeof App !== "undefined" && App && App.theme) ? App.theme.showColorButton : true

    function mix(a, b, t) {
        t = Math.max(0, Math.min(1, t))
        return Qt.rgba(
            a.r * (1 - t) + b.r * t,
            a.g * (1 - t) + b.g * t,
            a.b * (1 - t) + b.b * t,
            a.a * (1 - t) + b.a * t
        )
    }
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function sp(v) { return Math.max(1, Math.round(v * fontScale)) }
    function fs(v) { return sp(v) }
    function dp(v) { return Math.max(1, Math.round(v * controlScale)) }
    function setBaseFontSize(px) {
        const next = Math.max(11, Math.min(20, Math.round(Number(px))))
        if (typeof App !== "undefined" && App && App.theme)
            App.theme.setFontScale(next / 13.0)
        else
            fontScale = next / 13.0
    }

    property color white: "#FFFFFF"
    property color black: "#000000"
    property color baseSurface: mode === "dark" ? "#10141C" : "#FFFBFE"
    property color baseSurfaceAlt: mode === "dark" ? "#151B25" : "#F8F7FC"
    property color baseCard: mode === "dark" ? "#1D2430" : "#FFFFFF"
    property color baseOutline: mode === "dark" ? "#465164" : "#D6D9E3"

    property color primaryText: "#FFFFFF"
    property color primaryStrong: mode === "dark" ? Qt.lighter(primary, 1.70) : primary
    property color primaryHover: Qt.lighter(primary, mode === "dark" ? 1.24 : 1.07)
    property color primaryPressed: Qt.darker(primary, mode === "dark" ? 1.02 : 1.14)
    property color primarySoft: mix(baseSurface, primary, mode === "dark" ? 0.26 : 0.08)
    property color primarySoftHover: mix(baseSurface, primary, mode === "dark" ? 0.34 : 0.12)
    property color primarySoftPressed: mix(baseSurface, primary, mode === "dark" ? 0.42 : 0.17)
    property color primaryOutline: alpha(primary, mode === "dark" ? 0.76 : 0.56)
    property color primaryContainer: mix(baseCard, primary, mode === "dark" ? 0.32 : 0.12)
    property color primaryContainerStrong: mix(baseCard, primary, mode === "dark" ? 0.46 : 0.20)

    property QtObject radius: QtObject {
        property int window: 12
        property int button: Math.max(5, theme.dp(6))
        property int popup: Math.max(8, theme.dp(10))
        property int card: Math.max(10, theme.dp(12))
    }

    property QtObject metrics: QtObject {
        property int titleBarHeight: Math.max(34, theme.dp(36))
        property int controlHeight: Math.max(30, theme.dp(30))
        property int fieldHeight: Math.max(38, theme.dp(40))
        property int navWidthDefault: Math.max(98, theme.dp(106))
        property int navWidthMax: Math.max(126, theme.dp(132))
        property int navIconOnlyThreshold: Math.max(54, theme.dp(62))
        property int navIconWidth: Math.max(42, theme.dp(46))
        property int navItemHeight: Math.max(34, theme.dp(36))
        property int shadowMargin: Math.max(9, theme.dp(9))
        property int pagePadding: Math.max(14, theme.dp(18))
        property int cardPadding: theme.dp(18)
        property int spacing: theme.dp(12)
    }

    property QtObject fontSize: QtObject {
        property int tiny: theme.sp(10)
        property int small: theme.sp(11)
        property int caption: theme.sp(12)
        property int control: theme.sp(13)
        property int body: theme.sp(14)
        property int subtitle: theme.sp(16)
        property int title: theme.sp(24)
        property int hero: theme.sp(28)
    }

    property int fontTiny: fontSize.tiny
    property int fontSmall: fontSize.small
    property int fontNormal: fontSize.control
    property int fontBody: fontSize.body
    property int fontTitle: fontSize.title
    property int fontButton: fontSize.control
    property int fontSectionTitle: fontSize.subtitle

    property QtObject color: QtObject {
        property color surface: theme.mix(theme.baseSurface, theme.primary, theme.mode === "dark" ? 0.10 : 0.045)
        property color surfaceAlt: theme.mix(theme.baseSurfaceAlt, theme.primary, theme.mode === "dark" ? 0.14 : 0.060)
        property color titleBar: theme.mix(theme.baseSurfaceAlt, theme.primary, theme.mode === "dark" ? 0.25 : 0.10)
        property color card: theme.mix(theme.baseCard, theme.primary, theme.mode === "dark" ? 0.12 : 0.045)
        property color cardAlt: theme.mix(theme.baseCard, theme.primary, theme.mode === "dark" ? 0.22 : 0.09)
        property color sidebar: theme.mix(theme.baseSurfaceAlt, theme.primary, theme.mode === "dark" ? 0.30 : 0.120)
        property color sidebarHover: theme.mix(theme.baseSurfaceAlt, theme.primary, theme.mode === "dark" ? 0.35 : 0.13)
        property color sidebarAccent: theme.alpha(theme.primary, theme.mode === "dark" ? 0.17 : 0.09)
        property color navActive: theme.primaryContainer
        property color navActiveStrong: theme.primaryContainerStrong
        property color navSelectedText: theme.mode === "dark" ? "#FFFFFF" : theme.primaryStrong
        property color navSelectedIcon: theme.mode === "dark" ? "#FFFFFF" : theme.primaryStrong

        property color text: theme.mode === "dark" ? "#F4F7FF" : "#22242B"
        property color textOnPrimary: theme.primaryText
        property color icon: theme.mode === "dark" ? "#EEF3FF" : "#2A2D35"
        property color mutedText: theme.mode === "dark" ? "#C8D0E0" : "#5E6472"
        property color outline: theme.mix(theme.baseOutline, theme.primary, theme.mode === "dark" ? 0.18 : 0.14)
        property color outlineAccent: theme.primaryOutline
        property color hairline: theme.mix(theme.baseOutline, theme.primary, theme.mode === "dark" ? 0.12 : 0.08)

        property color controlHover: theme.mode === "dark"
            ? theme.mix(theme.mix(theme.baseSurfaceAlt, theme.primary, 0.28), theme.white, 0.08)
            : theme.mix(theme.mix(theme.baseSurfaceAlt, theme.primary, 0.04), theme.black, 0.055)
        property color controlPressed: theme.mode === "dark"
            ? theme.mix(theme.mix(theme.baseSurfaceAlt, theme.primary, 0.34), theme.white, 0.12)
            : theme.mix(theme.mix(theme.baseSurfaceAlt, theme.primary, 0.07), theme.black, 0.085)
        property color controlChecked: theme.primaryContainer
        property color field: theme.mix(theme.baseCard, theme.primary, theme.mode === "dark" ? 0.08 : 0.02)
        property color fieldFocus: theme.mix(theme.baseCard, theme.primary, theme.mode === "dark" ? 0.16 : 0.06)
        property color fieldFocusBorder: theme.mode === "dark" ? Qt.lighter(theme.primary, 1.85) : theme.primaryStrong
        property color selection: theme.mode === "dark" ? theme.alpha(Qt.lighter(theme.primary, 1.85), 0.62) : theme.alpha(theme.primary, 0.34)
        property color selectedText: theme.mode === "dark" ? "#FFFFFF" : "#FFFFFF"
        property color hero: theme.mix(theme.baseCard, theme.primary, theme.mode === "dark" ? 0.40 : 0.15)

        property color accentLine: theme.primary
        property color dangerHover: theme.mode === "dark" ? "#522123" : "#FCEEEE"
        property color dangerPressed: theme.mode === "dark" ? "#6F2B2D" : "#FFDADA"
        property color dangerText: theme.mode === "dark" ? "#FFB4AB" : "#BA1A1A"
        property color shadow: theme.mode === "dark" ? "#AA000000" : "#3E000000"
        property color menuShadow: theme.mode === "dark" ? "#C0000000" : "#33000000"
    }

    function previewSurface(nextMode) { return nextMode === "dark" ? "#10141C" : "#FFFBFE" }



}
