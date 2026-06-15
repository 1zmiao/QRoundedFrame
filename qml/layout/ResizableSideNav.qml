import QtQuick
import QtQuick.Window
import "../core" as Core
import "../controls"

Item {
    id: root

    readonly property real devicePixelRatio: Math.max(1.0, (root.Window.window && root.Window.window.screen) ? root.Window.window.screen.devicePixelRatio : Screen.devicePixelRatio)
    readonly property real physicalPixel: 1.0 / devicePixelRatio
    function snapToPhysicalPixel(value) {
        return Math.round(value / physicalPixel) * physicalPixel
    }

    property int expandedWidth: Core.Theme.metrics.navWidthDefault
    property int compactWidth: Core.Theme.metrics.navIconWidth
    property int minWidthBeforeHidden: Core.Theme.dp(18)
    property int restoreWidth: expandedWidth
    property string currentPage: "home"
    property real startWidth: width
    property int cornerRadius: Core.Theme.radius.window
    property string sideGlowModeKey: Core.Theme.mode
    property string sideGlowHex: String(Core.Theme.primary).replace("#", "")
    property bool lowMemoryVisuals: Core.Theme.lowMemoryMode
    property real sideGlowRenderScaleX: 1.0
    property real sideGlowRenderScaleY: 0.50
    property int sideGlowPixelWidth: Math.max(12, Math.round(34 * sideGlowRenderScaleX))
    property int sideGlowPixelHeight: Math.max(96, Math.round(768 * sideGlowRenderScaleY / 48) * 48)
    property string currentSideGlowSource: sideGlowSource(sideGlowModeKey, sideGlowHex)
    property string pendingSideGlowSource: ""
    property bool sideGlowSwapping: false
    property string pendingIntentPage: ""

    signal pageIntent(string page)

    function queuePageIntent(page) {
        pendingIntentPage = String(page || "")
        if (pendingIntentPage.length > 0)
            pageIntentDelay.restart()
    }

    function cancelPageIntent(page) {
        if (pendingIntentPage === String(page || "")) {
            pageIntentDelay.stop()
            pendingIntentPage = ""
        }
    }

    function sideGlowSource(mode, hex) {
        return "image://cardaccent/side/" + mode + "/" + hex + "/" + root.cornerRadius + "/" + root.sideGlowPixelWidth + "x" + root.sideGlowPixelHeight + "/" + root.sideGlowRenderScaleX.toFixed(3) + "x" + root.sideGlowRenderScaleY.toFixed(3)
    }

    function refreshSideGlow() {
        if (!sideGlowSwapping)
            currentSideGlowSource = sideGlowSource(sideGlowModeKey, sideGlowHex)
    }

    function swapSideGlow(mode) {
        const nextSource = sideGlowSource(mode, sideGlowHex)
        if (nextSource === currentSideGlowSource)
            return
        sideGlowSwapping = true
        pendingSideGlowSource = nextSource
        nextSideEdgeGlow.opacity = 0
        nextSideEdgeGlow.source = nextSource
        sideGlowFadeOut.stop()
        sideGlowFadeIn.stop()
        sideGlowFadeOut.from = sideEdgeGlow.opacity
        sideGlowFadeOut.to = 0
        sideGlowFadeIn.from = 0
        sideGlowFadeIn.to = sideGlowOpacityForMode(mode)
        sideGlowFadeOut.start()
        sideGlowFadeIn.start()
    }

    function finishSideGlowSwap() {
        if (!sideGlowSwapping)
            return
        sideGlowModeKey = Core.Theme.mode
        currentSideGlowSource = pendingSideGlowSource.length > 0 ? pendingSideGlowSource : sideGlowSource(sideGlowModeKey, sideGlowHex)
        sideEdgeGlow.opacity = sideGlowOpacityForMode(sideGlowModeKey)
        nextSideEdgeGlow.opacity = 0
        nextSideEdgeGlow.source = ""
        pendingSideGlowSource = ""
        sideGlowSwapping = false
    }

    function sideGlowOpacityForMode(mode) {
        return 1.0
    }

    function persistWidthLater() {
        Qt.callLater(function() {
            if (typeof App !== "undefined" && App && App.settings)
                App.settings.setValue("layout/navWidth", Math.round(root.width))
        })
    }

    function hide() {
        if (width > compactWidth)
            restoreWidth = width
        width = 0
        persistWidthLater()
    }

    function restore() {
        width = snapToPhysicalPixel(restoreWidth > compactWidth ? restoreWidth : expandedWidth)
        persistWidthLater()
    }

    function toggle() {
        if (width <= 0)
            restore()
        else
            hide()
    }

    function applyWidth(next) {
        if (next < minWidthBeforeHidden)
            width = 0
        else if (next < compactWidth)
            width = snapToPhysicalPixel(compactWidth)
        else
            width = snapToPhysicalPixel(Math.max(compactWidth, Math.min(Core.Theme.dp(260), next)))
    }

    function snapCurrentWidthLater() {
        Qt.callLater(function() {
            if (root.width > 0)
                root.width = snapToPhysicalPixel(root.width)
        })
    }

    onDevicePixelRatioChanged: snapCurrentWidthLater()
    onSideGlowHexChanged: refreshSideGlow()
    onCornerRadiusChanged: refreshSideGlow()
    onSideGlowPixelWidthChanged: refreshSideGlow()
    onSideGlowPixelHeightChanged: refreshSideGlow()
    Component.onCompleted: snapCurrentWidthLater()

    Item {
        id: bgLayer
        anchors.fill: parent
        visible: root.width > 0
        clip: true

        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            antialiasing: true
            color: Core.Theme.color.sidebar
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: root.cornerRadius + 2
            color: Core.Theme.color.sidebar
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
        }
        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: root.cornerRadius + 2
            color: Core.Theme.color.sidebar
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
        }

        BackgroundRipple {
            anchors.fill: parent
            z: 1
            radius: root.cornerRadius
            colorRole: "sidebar"
            opacityScale: 1.0
        }
    }

    Image {
        id: sideEdgeGlow
        z: 0.5
        width: 34
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        sourceSize.width: root.sideGlowPixelWidth
        sourceSize.height: root.sideGlowPixelHeight
        source: root.currentSideGlowSource
        fillMode: Image.Stretch
        smooth: true
        asynchronous: false
        mipmap: false
        cache: false
        retainWhileLoading: false
        visible: root.width > 0
        opacity: root.sideGlowOpacityForMode(root.sideGlowModeKey)
    }

    Image {
        id: nextSideEdgeGlow
        z: 0.55
        width: 34
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        sourceSize.width: root.sideGlowPixelWidth
        sourceSize.height: root.sideGlowPixelHeight
        fillMode: Image.Stretch
        smooth: true
        asynchronous: false
        mipmap: false
        cache: false
        retainWhileLoading: false
        visible: root.width > 0 && (opacity > 0.001 || String(source).length > 0)
        opacity: 0
    }

    NumberAnimation {
        id: sideGlowFadeOut
        target: sideEdgeGlow
        property: "opacity"
        duration: Core.Theme.animatedColorTransitionMs
        easing.type: Easing.InOutCubic
    }

    NumberAnimation {
        id: sideGlowFadeIn
        target: nextSideEdgeGlow
        property: "opacity"
        duration: Core.Theme.animatedColorTransitionMs
        easing.type: Easing.InOutCubic
        onFinished: root.finishSideGlowSwap()
    }

    Connections {
        target: (typeof App !== "undefined" && App && App.theme) ? App.theme : null
        function onModeChanged(mode) { root.swapSideGlow(mode) }
    }

    Timer {
        id: pageIntentDelay
        interval: 120
        repeat: false
        onTriggered: {
            if (root.pendingIntentPage.length > 0)
                root.pageIntent(root.pendingIntentPage)
            root.pendingIntentPage = ""
        }
    }

    Column {
        id: navColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: settingsDock.top
        anchors.margins: Core.Theme.dp(6)
        spacing: Core.Theme.dp(4)
        visible: root.width > 0

        Repeater {
            model: Core.AppInfo.navPageKeys

            delegate: NavItem {
                width: navColumn.width
                page: modelData
                label: Core.AppInfo.pageTitle(modelData)
                iconName: Core.AppInfo.pageIcon(modelData)
            }
        }
    }

    Item {
        id: settingsDock
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Core.Theme.dp(6)
        height: root.width > 0 ? Core.Theme.metrics.navItemHeight : 0
        visible: root.width > 0

        NavItem { anchors.fill: parent; page: "settings"; label: Core.AppInfo.pageTitle("settings"); iconName: Core.AppInfo.pageIcon("settings") }
    }

    Rectangle {
        id: handle
        width: 5
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        color: "transparent"
        visible: root.width > 0


        DragHandler {
            target: null
            onActiveChanged: {
                if (active)
                    root.startWidth = root.width
                else
                    root.persistWidthLater()
            }
            onTranslationChanged: if (active) root.applyWidth(root.startWidth + translation.x)
        }

        MouseArea { anchors.fill: parent; cursorShape: Qt.SplitHCursor; acceptedButtons: Qt.NoButton }
    }

    component NavItem: Item {
        id: item
        property string page: ""
        property string label: ""
        property string iconName: ""
        property bool selected: page === root.currentPage
        property bool compact: root.width <= Core.Theme.metrics.navIconOnlyThreshold

        height: Core.Theme.metrics.navItemHeight

        Rectangle {
            anchors.fill: parent
            radius: Core.Theme.radius.button
            color: item.selected ? (Core.Theme.mode === "dark" ? Core.Theme.color.navActiveStrong : Core.Theme.color.navActive) : (mouse.pressed ? Core.Theme.color.controlPressed : (mouse.containsMouse ? Core.Theme.color.controlHover : Core.Theme.alpha(Core.Theme.color.controlHover, 0)))
            border.color: item.selected ? (Core.Theme.mode === "dark" ? Core.Theme.alpha(Qt.lighter(Core.Theme.primary, 1.8), 0.92) : Core.Theme.primaryOutline) : Core.Theme.alpha(Core.Theme.primaryOutline, 0)
            border.width: item.selected ? 1 : 0
            Behavior on color { ColorAnimation { duration: item.selected ? Core.Theme.animatedColorTransitionMs : Core.Theme.controlTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
        }

        Rectangle {
            visible: !item.compact
            width: item.selected ? Core.Theme.dp(4) : Core.Theme.dp(2)
            height: item.selected ? Core.Theme.dp(20) : Core.Theme.dp(13)
            radius: width / 2
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            color: item.selected
                   ? (Core.Theme.mode === "dark" ? Qt.lighter(Core.Theme.primary, 1.95) : Core.Theme.primary)
                   : (Core.Theme.mode === "dark"
                      ? Core.Theme.alpha(Qt.lighter(Core.Theme.primary, 1.65), mouse.containsMouse ? 0.62 : 0.40)
                      : Core.Theme.alpha(Core.Theme.primary, mouse.containsMouse ? 0.46 : 0.28))
            opacity: item.selected || mouse.containsMouse ? 1.0 : 0.72
            Behavior on width { NumberAnimation { duration: Core.Theme.controlTransitionMs; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: Core.Theme.controlTransitionMs; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on opacity { NumberAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
        }

        IconImage {
            x: item.compact ? Math.round((parent.width - width) / 2) : Core.Theme.dp(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Core.Theme.dp(18)
            height: width
            iconName: item.iconName
            iconColor: item.selected ? Core.Theme.color.navSelectedIcon : Core.Theme.color.icon
            strokeWidth: 1.05
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: Core.Theme.dp(36)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: item.label
            visible: !item.compact
            color: item.selected ? Core.Theme.color.navSelectedText : Core.Theme.color.text
            font.pixelSize: Core.Theme.fontSize.control
            font.family: Core.Theme.appFontFamily
            font.bold: item.selected
            elide: Text.ElideRight
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            onEntered: root.queuePageIntent(item.page)
            onExited: root.cancelPageIntent(item.page)
            onPressed: root.pageIntent(item.page)
            onClicked: root.currentPage = item.page
        }
    }
}
