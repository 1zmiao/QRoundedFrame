import QtQuick
import "../core" as Core

Canvas {
    id: root

    property int radius: Core.Theme.radius.popup
    property int shadowSize: Core.Theme.dp(10)
    property color shadowColor: Core.Theme.color.shadow
    property real strength: Core.Theme.mode === "dark" ? 0.34 : 0.22

    antialiasing: true
    renderTarget: Canvas.FramebufferObject

    onPaint: {
        const ctx = getContext("2d")
        const w = width
        const h = height
        ctx.clearRect(0, 0, w, h)
        const s = Math.max(2, root.shadowSize)
        const rx = s
        const ry = s
        const rw = Math.max(1, w - s * 2)
        const rh = Math.max(1, h - s * 2)
        for (let i = s; i >= 1; --i) {
            const t = i / s
            const alpha = root.strength * Math.pow(1 - t, 1.8) * 0.18
            ctx.strokeStyle = rgba(root.shadowColor, alpha)
            ctx.lineWidth = 2
            roundedRect(ctx, rx - i, ry - i, rw + i * 2, rh + i * 2, root.radius + i)
            ctx.stroke()
        }
    }

    function rgba(c, a) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + Math.max(0, Math.min(1, a)) + ")"
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

    onRadiusChanged: requestPaint()
    onShadowSizeChanged: requestPaint()
    onShadowColorChanged: requestPaint()
    onStrengthChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Connections {
        target: Core.Theme
        function onModeChanged() { root.requestPaint() }
        function onPrimaryChanged() { root.requestPaint() }
        function onFontScaleChanged() { root.requestPaint() }
    }
}
