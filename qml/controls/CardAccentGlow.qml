import QtQuick
import "../core" as Core

Item {
    id: root

    property int radius: Core.Theme.radius.card
    property string liveHex: String(Core.Theme.primary).replace("#", "")
    property string modeKey: Core.Theme.mode
    // The accent image is a soft glow that is stretched to the card bounds.
    // Bucket dimensions aggressively so live window resizing does not request
    // a new provider image for every single pixel delta.
    property bool liveResizeLowResolution: root.Window.window
                                           && root.Window.window.nativeSizeMoveActive !== undefined
                                           && root.Window.window.nativeSizeMoveActive
    property bool lowMemoryVisuals: Core.Theme.lowMemoryMode
    property bool childWindowLowMemoryVisuals: Core.Theme.lowMemoryMode
                                                && root.Window.window
                                                && root.Window.window.windowKey !== undefined
                                                && String(root.Window.window.windowKey) !== "main"
    property real renderScaleX: 0.50
    property real renderScaleY: 1.0
    property int renderStep: liveResizeLowResolution ? 128 : (lowMemoryVisuals ? 64 : 48)
    property int pixelWidth: Math.max(24, Math.round((width * renderScaleX) / renderStep) * renderStep)
    property int pixelHeight: Math.max(24, Math.round((height * renderScaleY) / renderStep) * renderStep)
    property int pixelRadius: Math.max(0, Math.round(radius))
    property bool glowSwapPending: false
    property string pendingImageSource: ""
    property bool diagnosticDisabled: typeof App !== "undefined"
                                      && App
                                      && String(App.envValue("QROUNDEDFRAME_DISABLE_CARD_ACCENT_GLOW")).toLowerCase() === "1"
    property bool effectEnabled: Core.Theme.decorativeEffectsEnabled && !diagnosticDisabled && !childWindowLowMemoryVisuals && width > 0 && height > 0

    anchors.fill: parent
    visible: effectEnabled

    function imageName() {
        return "image://cardaccent/card/" + root.modeKey + "/" + root.liveHex + "/" + root.pixelRadius + "/" + root.pixelWidth + "x" + root.pixelHeight + "/" + root.renderScaleX.toFixed(3) + "x" + root.renderScaleY.toFixed(3)
    }

    function unloadImages() {
        currentFade.stop()
        nextFade.stop()
        currentImage.source = ""
        nextImage.source = ""
        currentImage.opacity = 1.0
        nextImage.opacity = 0.0
        root.pendingImageSource = ""
        root.glowSwapPending = false
    }

    Item {
        anchors.fill: parent
        visible: root.visible

        Image {
            id: currentImage
            anchors.fill: parent
            sourceSize.width: root.pixelWidth
            sourceSize.height: root.pixelHeight
            fillMode: Image.Stretch
            smooth: true
            asynchronous: false
            mipmap: false
            cache: false
            retainWhileLoading: false
            opacity: 1.0
        }

        Image {
            id: nextImage
            anchors.fill: parent
            sourceSize.width: root.pixelWidth
            sourceSize.height: root.pixelHeight
            fillMode: Image.Stretch
            smooth: true
            asynchronous: false
            mipmap: false
            cache: false
            retainWhileLoading: false
            opacity: 0.0
            visible: opacity > 0.001 || String(source).length > 0
        }

        Connections {
            target: root
            function onEffectEnabledChanged() {
                if (root.effectEnabled)
                    root.updateSizeOnly()
                else
                    root.unloadImages()
            }
            function onLiveHexChanged() { root.updateSizeOnly() }
            function onModeKeyChanged() { root.scheduleGlowSwap() }
            function onPixelWidthChanged() { if (!root.liveResizeLowResolution) root.updateSizeOnly() }
            function onPixelHeightChanged() { if (!root.liveResizeLowResolution) root.updateSizeOnly() }
            function onPixelRadiusChanged() { root.updateSizeOnly() }
            function onLowMemoryVisualsChanged() {
                root.finishGlowSwap()
                root.updateSizeOnly()
            }
            function onChildWindowLowMemoryVisualsChanged() {
                if (root.childWindowLowMemoryVisuals)
                    root.unloadImages()
                else
                    root.updateSizeOnly()
            }
            function onRenderScaleXChanged() {
                root.finishGlowSwap()
                root.updateSizeOnly()
            }
            function onRenderScaleYChanged() {
                root.finishGlowSwap()
                root.updateSizeOnly()
            }
            function onLiveResizeLowResolutionChanged() {
                if (!root.liveResizeLowResolution)
                    root.updateSizeOnly()
            }
        }
    }

    Component.onCompleted: updateSizeOnly()

    function updateSizeOnly() {
        if (!root.visible)
            return
        const source = root.imageName()
        if (root.glowSwapPending) {
            nextImage.sourceSize.width = root.pixelWidth
            nextImage.sourceSize.height = root.pixelHeight
            nextImage.source = source
            root.pendingImageSource = source
            return
        }
        currentImage.sourceSize.width = root.pixelWidth
        currentImage.sourceSize.height = root.pixelHeight
        currentImage.source = source
    }

    function scheduleGlowSwap() {
        if (!root.visible)
            return
        const source = root.imageName()
        if (source === String(currentImage.source))
            return
        root.glowSwapPending = true
        root.pendingImageSource = source
        currentFade.stop()
        nextFade.stop()
        nextImage.sourceSize.width = root.pixelWidth
        nextImage.sourceSize.height = root.pixelHeight
        nextImage.opacity = 0.0
        nextImage.source = source
        currentFade.from = currentImage.opacity
        currentFade.to = 0.0
        nextFade.from = 0.0
        nextFade.to = 1.0
        currentFade.start()
        nextFade.start()
    }

    function finishGlowSwap() {
        if (!root.glowSwapPending)
            return
        currentFade.stop()
        nextFade.stop()
        currentImage.sourceSize.width = root.pixelWidth
        currentImage.sourceSize.height = root.pixelHeight
        currentImage.source = root.pendingImageSource.length > 0 ? root.pendingImageSource : root.imageName()
        currentImage.opacity = 1.0
        nextImage.opacity = 0.0
        nextImage.source = ""
        root.pendingImageSource = ""
        root.glowSwapPending = false
    }

    NumberAnimation {
        id: currentFade
        target: currentImage
        property: "opacity"
        duration: Core.Theme.animatedColorTransitionMs
        easing.type: Easing.InOutCubic
    }

    NumberAnimation {
        id: nextFade
        target: nextImage
        property: "opacity"
        duration: Core.Theme.animatedColorTransitionMs
        easing.type: Easing.InOutCubic
        onFinished: root.finishGlowSwap()
    }

    Component.onDestruction: {
        root.unloadImages()
    }
}
