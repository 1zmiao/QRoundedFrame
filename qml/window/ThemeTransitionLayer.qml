import QtQuick
import "../core" as Core

Item {
    id: root
    visible: running
    enabled: false

    property int radius: 12
    property color baseColor: Core.Theme.color.surface
    property color rippleColor: Core.Theme.color.surface
    property var delays: [0, 205, 410, 615]
    property real maxRadius: Math.sqrt(width * width + height * height) + 72
    property real _cx: width / 2
    property real _cy: height / 2
    property bool running: false
    property real timeMs: 0
    property int rippleDuration: 1580
    property real opacityScale: 1.10
    property int startDelay: 0
    property int totalDuration: rippleDuration + 820
    property string colorRole: "surface"
    property real renderScale: 1.0

    signal finished()

    function play(x, y, nextMode) {
        playFrom(x, y, nextMode, Core.Theme.color.surface)
    }

    function playFrom(x, y, nextMode, fromColor) {
        _cx = x
        _cy = y
        baseColor = fromColor
        rippleColor = Core.Theme.previewSurface(nextMode)
        timeMs = 0
        running = true
        canvas.requestPaint()
        if (startDelay > 0)
            delayTimer.restart()
        else
            anim.restart()
    }

    Canvas {
        id: canvas
        readonly property real effectiveRenderScale: Math.max(0.15, Math.min(1.0, root.renderScale))
        x: 0
        y: 0
        width: Math.max(1, Math.ceil(root.width * effectiveRenderScale))
        height: Math.max(1, Math.ceil(root.height * effectiveRenderScale))
        scale: 1.0 / effectiveRenderScale
        transformOrigin: Item.TopLeft
        smooth: true
        antialiasing: true
        renderTarget: Canvas.FramebufferObject

        onPaint: {
            const ctx = getContext("2d")
            const renderScale = canvas.effectiveRenderScale
            const w = root.width
            const h = root.height
            ctx.setTransform(1, 0, 0, 1, 0, 0)
            ctx.clearRect(0, 0, width, height)
            ctx.setTransform(renderScale, 0, 0, renderScale, 0, 0)
            if (!root.running)
                return

            ctx.save()
            roundedRect(ctx, 0, 0, w, h, root.radius)
            ctx.clip()

            for (let i = 0; i < root.delays.length; ++i) {
                const t = (root.timeMs - root.delays[i]) / root.rippleDuration
                if (t <= 0 || t > 1)
                    continue

                const eased = 1 - Math.pow(1 - t, 3)
                const r = Math.max(2, eased * root.maxRadius)
                const soft = Math.max(92, r * 0.46)
                const inner = Math.max(0, r - soft)
                const luma = root.rippleColor.r * 0.299 + root.rippleColor.g * 0.587 + root.rippleColor.b * 0.114
                const contrastBoost = luma > 0.70 ? 1.34 : (luma < 0.34 ? 1.22 : 1.08)
                const baseOpacity = Math.max(0.20, 0.56 - i * 0.07) * root.opacityScale * contrastBoost
                const fade = 1 - Math.max(0, t - 0.70) / 0.30
                const originFade = Math.min(1, Math.max(0, (t - 0.055) / 0.24))
                const alpha = Math.max(0, baseOpacity * Math.min(1, fade) * originFade)
                if (alpha <= 0.001)
                    continue

                const g = ctx.createRadialGradient(root._cx, root._cy, inner, root._cx, root._cy, r)
                g.addColorStop(0.0, rgba(root.rippleColor, 0.0))
                g.addColorStop(0.22, rgba(root.rippleColor, 0.0))
                g.addColorStop(0.54, rgba(root.rippleColor, alpha * 0.78))
                g.addColorStop(0.88, rgba(root.rippleColor, alpha * 0.40))
                g.addColorStop(1.0, rgba(root.rippleColor, 0.0))
                ctx.fillStyle = g
                ctx.fillRect(0, 0, w, h)
            }

            ctx.restore()
        }

        function rgba(c, a) {
            return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")"
        }

        function roundedRect(ctx, x, y, w, h, r) {
            r = Math.max(0, Math.min(r, Math.min(w, h) / 2))
            ctx.beginPath()
            ctx.moveTo(x + r, y)
            ctx.lineTo(x + w - r, y)
            ctx.quadraticCurveTo(x + w, y, x + w, y + r)
            ctx.lineTo(x + w, y + h - r)
            ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h)
            ctx.lineTo(x + r, y + h)
            ctx.quadraticCurveTo(x, y + h, x, y + h - r)
            ctx.lineTo(x, y + r)
            ctx.quadraticCurveTo(x, y, x + r, y)
            ctx.closePath()
        }
    }

    Timer {
        id: delayTimer
        interval: root.startDelay
        repeat: false
        onTriggered: anim.restart()
    }

    NumberAnimation {
        id: anim
        target: root
        property: "timeMs"
        from: 0
        to: root.totalDuration
        duration: root.totalDuration
        easing.type: Easing.Linear
        onFinished: {
            root.running = false
            root.timeMs = 0
            canvas.requestPaint()
            root.finished()
        }
    }

    onTimeMsChanged: canvas.requestPaint()
    onRadiusChanged: canvas.requestPaint()
    onRippleColorChanged: canvas.requestPaint()
}
