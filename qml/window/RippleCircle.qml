import QtQuick

Item {
    id: root
    visible: running
    enabled: false

    property real centerX: width / 2
    property real centerY: height / 2
    property real progress: 0.0
    property real maxRadius: 1000
    property real clipRadius: 12
    property int delayMs: 0
    property color rippleColor: "white"
    property real opacityFactor: 0.4
    property bool running: false

    signal finished()

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
            if (!root.running || root.progress <= 0)
                return

            const r = Math.max(1, root.progress * root.maxRadius)
            const soft = Math.max(36, r * 0.18)
            const inner = Math.max(0, r - soft)

            ctx.save()
            roundedRect(ctx, 0, 0, w, h, root.clipRadius)
            ctx.clip()

            const g = ctx.createRadialGradient(root.centerX, root.centerY, inner, root.centerX, root.centerY, r)
            const c = root.rippleColor
            g.addColorStop(0.0, rgba(c, root.opacityFactor))
            g.addColorStop(0.74, rgba(c, root.opacityFactor * 0.70))
            g.addColorStop(1.0, rgba(c, 0.0))
            ctx.fillStyle = g
            ctx.fillRect(0, 0, w, h)
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
        interval: root.delayMs
        repeat: false
        onTriggered: grow.restart()
    }

    NumberAnimation {
        id: grow
        target: root
        property: "progress"
        from: 0.0
        to: 1.0
        duration: 620
        easing.type: Easing.OutCubic
        onStopped: canvas.requestPaint()
        onFinished: {
            root.running = false
            root.progress = 0.0
            canvas.requestPaint()
            root.finished()
        }
    }

    function restart() {
        progress = 0.0
        running = true
        canvas.requestPaint()
        delayTimer.restart()
    }

    onProgressChanged: canvas.requestPaint()
    onRippleColorChanged: canvas.requestPaint()
    onClipRadiusChanged: canvas.requestPaint()
}
