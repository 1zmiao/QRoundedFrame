import QtQuick
import "../core" as Core

Item {
    id: root
    visible: running
    enabled: false

    property int radius: 12
    property color baseColor: Core.Theme.color.surface
    property color rippleColor: Core.Theme.color.surface
    property var delays: [0, 130, 260, 390, 520]
    property real maxRadius: Math.sqrt(width * width + height * height) + 72
    property real _cx: width / 2
    property real _cy: height / 2
    property bool running: false
    property real timeMs: 0
    property int rippleDuration: 1040
    property real opacityScale: 1.0
    property int startDelay: 0
    property int totalDuration: rippleDuration + 720

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
        anchors.fill: parent
        antialiasing: true
        renderTarget: Canvas.FramebufferObject

        onPaint: {
            const ctx = getContext("2d")
            const w = width
            const h = height
            ctx.clearRect(0, 0, w, h)
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
                const soft = Math.max(62, r * 0.34)
                const inner = Math.max(0, r - soft)
                const lightBoost = (root.rippleColor.r + root.rippleColor.g + root.rippleColor.b) / 3 > 0.70 ? 1.38 : 1.0
                const baseOpacity = Math.max(0.18, 0.52 - i * 0.07) * root.opacityScale * lightBoost
                const fade = 1 - Math.max(0, t - 0.70) / 0.30
                const alpha = Math.max(0, baseOpacity * Math.min(1, fade))

                const g = ctx.createRadialGradient(root._cx, root._cy, inner, root._cx, root._cy, r)
                g.addColorStop(0.0, rgba(root.rippleColor, alpha * 0.95))
                g.addColorStop(0.50, rgba(root.rippleColor, alpha * 0.70))
                g.addColorStop(0.84, rgba(root.rippleColor, alpha * 0.34))
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
