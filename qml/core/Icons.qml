pragma Singleton
import QtQuick

QtObject {
    // Centralized icon registry. All navigation, title-bar, field, dialog, and
    // tray/menu glyphs should be added here so app-wide icon replacement is easy.
    function name(iconName) {
        if (iconName === "home") return "⌂"
        if (iconName === "settings") return "☷"
        if (iconName === "tools") return "◇"
        if (iconName === "update") return "↻"
        if (iconName === "about") return "i"
        if (iconName === "menu") return "☰"
        if (iconName === "lock") return "⌑"
        if (iconName === "unlock") return "⌐"
        return "•"
    }

    function cssColor(c) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + c.a + ")"
    }

    function drawIcon(ctx, iconName, w, h, color, strokeWidth) {
        const sx = w / 17.0
        const sy = h / 17.0
        function x(v) { return v * sx }
        function y(v) { return v * sy }
        function line(x1, y1, x2, y2) {
            ctx.beginPath(); ctx.moveTo(x(x1), y(y1)); ctx.lineTo(x(x2), y(y2)); ctx.stroke()
        }
        function circle(cx, cy, r, fill) {
            ctx.beginPath(); ctx.arc(x(cx), y(cy), Math.max(sx, sy) * r, 0, Math.PI * 2)
            if (fill) ctx.fill(); else ctx.stroke()
        }
        function rect(rx, ry, rw, rh) {
            ctx.strokeRect(x(rx), y(ry), x(rw), y(rh))
        }
        function roundedRect(rx, ry, rw, rh, rr) {
            const r = rr
            ctx.beginPath()
            ctx.moveTo(x(rx + r), y(ry))
            ctx.lineTo(x(rx + rw - r), y(ry))
            ctx.quadraticCurveTo(x(rx + rw), y(ry), x(rx + rw), y(ry + r))
            ctx.lineTo(x(rx + rw), y(ry + rh - r))
            ctx.quadraticCurveTo(x(rx + rw), y(ry + rh), x(rx + rw - r), y(ry + rh))
            ctx.lineTo(x(rx + r), y(ry + rh))
            ctx.quadraticCurveTo(x(rx), y(ry + rh), x(rx), y(ry + rh - r))
            ctx.lineTo(x(rx), y(ry + r))
            ctx.quadraticCurveTo(x(rx), y(ry), x(rx + r), y(ry))
            ctx.stroke()
        }

        ctx.save()
        ctx.lineWidth = strokeWidth || 1.05
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.strokeStyle = cssColor(color)
        ctx.fillStyle = cssColor(color)

        if (iconName === "home") {
            line(3.5, 8.2, 8.5, 4.2); line(8.5, 4.2, 13.5, 8.2)
            line(5.0, 7.6, 5.0, 13.0); line(12.0, 7.6, 12.0, 13.0); line(5.0, 13.0, 12.0, 13.0)
        } else if (iconName === "settings") {
            // Sliders icon: avoids the gear/sun ambiguity at small sizes.
            line(3.2, 5.0, 13.8, 5.0); circle(6.0, 5.0, 1.05, false)
            line(3.2, 8.5, 13.8, 8.5); circle(10.8, 8.5, 1.05, false)
            line(3.2, 12.0, 13.8, 12.0); circle(7.8, 12.0, 1.05, false)
        } else if (iconName === "tools") {
            line(5, 12.5, 12.2, 5.3); line(10.4, 3.8, 13.2, 6.6); line(3.8, 10.8, 6.6, 13.6)
            circle(5.0, 5.3, 1.1, false); line(6.0, 6.2, 10.7, 10.9)
        } else if (iconName === "update") {
            ctx.beginPath(); ctx.arc(x(8.5), y(8.5), Math.max(sx, sy) * 5.2, Math.PI * 0.2, Math.PI * 1.55); ctx.stroke()
            line(3.2, 8.2, 4.1, 4.9); line(3.2, 8.2, 6.4, 7.4)
        } else if (iconName === "about") {
            circle(8.5, 8.5, 6.0, false); line(8.5, 7.4, 8.5, 12.0); circle(8.5, 5.0, 0.55, true)
        } else if (iconName === "minimize") {
            line(4, 10.5, 13, 10.5)
        } else if (iconName === "close") {
            line(4.9, 4.9, 12.1, 12.1); line(12.1, 4.9, 4.9, 12.1)
        } else if (iconName === "maximize") {
            line(5, 12, 12.3, 4.7); line(12.3, 4.7, 12.3, 9); line(12.3, 4.7, 8, 4.7)
            line(4.7, 12.3, 4.7, 9); line(4.7, 12.3, 8, 12.3)
        } else if (iconName === "restore") {
            roundedRect(4.5, 6.5, 7, 7, 1.1); roundedRect(7, 3.5, 7, 7, 1.1)
        } else if (iconName === "moon") {
            // Minimal hollow crescent: two clean curved strokes, not a circle.
            ctx.beginPath()
            ctx.moveTo(x(11.9), y(3.7))
            ctx.bezierCurveTo(x(7.4), y(4.2), x(4.7), y(7.8), x(5.7), y(11.0))
            ctx.bezierCurveTo(x(6.8), y(14.4), x(10.9), y(15.0), x(13.2), y(12.0))
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(x(10.5), y(4.6))
            ctx.bezierCurveTo(x(8.1), y(6.0), x(7.5), y(9.6), x(9.6), y(11.8))
            ctx.bezierCurveTo(x(10.5), y(12.8), x(11.9), y(13.2), x(13.2), y(12.0))
            ctx.stroke()
        } else if (iconName === "sun") {
            circle(8.5, 8.5, 2.8, false)
            for (let i = 0; i < 8; ++i) {
                const a = i * Math.PI / 4
                line(8.5 + Math.cos(a) * 5.4, 8.5 + Math.sin(a) * 5.4,
                     8.5 + Math.cos(a) * 6.8, 8.5 + Math.sin(a) * 6.8)
            }
        } else if (iconName === "pin" || iconName === "pin-filled") {
            ctx.beginPath()
            ctx.moveTo(x(6), y(3.9)); ctx.lineTo(x(11), y(3.9)); ctx.lineTo(x(10), y(8.1)); ctx.lineTo(x(13), y(11.2)); ctx.lineTo(x(4), y(11.2)); ctx.lineTo(x(7), y(8.1)); ctx.closePath()
            if (iconName === "pin-filled") ctx.fill(); else ctx.stroke()
            line(8.5, 11.2, 8.5, 15)
        } else if (iconName === "palette") {
            circle(8.5, 8.5, 5.8, false)
            circle(6.1, 6.6, 0.6, true); circle(9.0, 5.3, 0.6, true); circle(11.2, 7.3, 0.6, true)
            ctx.beginPath(); ctx.arc(x(9.8), y(11), Math.max(sx, sy) * 1.2, 0, Math.PI * 2); ctx.stroke()
        } else if (iconName === "menu") {
            line(4.5, 5.8, 12.5, 5.8); line(4.5, 8.5, 12.5, 8.5); line(4.5, 11.2, 12.5, 11.2)
        } else if (iconName === "drag") {
            circle(8.5, 8.5, 0.95, true)
            line(8.5, 4.0, 8.5, 6.2); line(8.5, 4.0, 7.5, 5.0); line(8.5, 4.0, 9.5, 5.0)
            line(8.5, 13.0, 8.5, 10.8); line(8.5, 13.0, 7.5, 12.0); line(8.5, 13.0, 9.5, 12.0)
            line(4.0, 8.5, 6.2, 8.5); line(4.0, 8.5, 5.0, 7.5); line(4.0, 8.5, 5.0, 9.5)
            line(13.0, 8.5, 10.8, 8.5); line(13.0, 8.5, 12.0, 7.5); line(13.0, 8.5, 12.0, 9.5)
        } else if (iconName === "lock" || iconName === "unlock") {
            roundedRect(4.7, 7.5, 7.6, 6.3, 1.0)
            ctx.beginPath()
            if (iconName === "unlock") {
                ctx.moveTo(x(6.0), y(7.5)); ctx.lineTo(x(6.0), y(6.4)); ctx.quadraticCurveTo(x(6.0), y(4.1), x(8.5), y(4.1)); ctx.quadraticCurveTo(x(10.1), y(4.1), x(10.8), y(5.2))
            } else {
                ctx.moveTo(x(6.0), y(7.5)); ctx.lineTo(x(6.0), y(6.0)); ctx.quadraticCurveTo(x(6.0), y(3.9), x(8.5), y(3.9)); ctx.quadraticCurveTo(x(11.0), y(3.9), x(11.0), y(6.0)); ctx.lineTo(x(11.0), y(7.5))
            }
            ctx.stroke()
        } else if (iconName === "page") {
            roundedRect(4.0, 3.5, 9.0, 10.0, 1.1)
            line(6.0, 6.3, 11.0, 6.3)
            line(6.0, 8.7, 10.5, 8.7)
            line(6.0, 11.1, 9.0, 11.1)
        } else if (iconName === "dialog") {
            roundedRect(3.5, 4.2, 10, 8.6, 1.2); line(5.5, 7, 11.5, 7); line(5.5, 9.4, 9.5, 9.4)
        } else if (iconName === "show") {
            roundedRect(3.6, 5.0, 9.8, 7.8, 1.1)
            line(5.5, 8.9, 8.0, 11.2)
            line(8.0, 11.2, 12.0, 7.0)
        } else if (iconName === "exit") {
            roundedRect(3.4, 4.2, 6.5, 8.6, 1.0)
            line(8.1, 8.5, 14.0, 8.5)
            line(12.0, 6.4, 14.0, 8.5)
            line(12.0, 10.6, 14.0, 8.5)
        } else {
            circle(8.5, 8.5, 1.3, true)
        }
        ctx.restore()
    }
}
