import QtQuick
import "../core" as Core

Item {
    id: root

    property real from: 0
    property real to: 100
    property real value: from
    property real stepSize: 1
    property int tickCount: 0
    property real visualPosition: to === from ? 0 : Math.max(0, Math.min(1, (value - from) / (to - from)))
    property bool hovered: mouseArea.containsMouse
    property bool pressed: mouseArea.pressed
    property bool dragging: false

    signal moved()
    signal committed()

    implicitHeight: Core.Theme.dp(32)
    height: implicitHeight

    function normalized(v) {
        var lo = Math.min(from, to)
        var hi = Math.max(from, to)
        var next = Math.max(lo, Math.min(hi, Number(v)))
        if (stepSize > 0)
            next = Math.round((next - from) / stepSize) * stepSize + from
        return Math.max(lo, Math.min(hi, next))
    }

    function setValueFromX(x, emitMoved) {
        var span = Math.max(1, track.width - handle.width)
        var local = Math.max(0, Math.min(span, x - track.x - handle.width / 2))
        var ratio = local / span
        var next = normalized(from + (to - from) * ratio)
        if (next !== value)
            value = next
        if (emitMoved)
            moved()
    }

    onFromChanged: value = normalized(value)
    onToChanged: value = normalized(value)
    onStepSizeChanged: value = normalized(value)
    Item {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Core.Theme.dp(18)

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: Core.Theme.dp(4)
            radius: 2
            color: Core.Theme.primarySoft
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: root.visualPosition * parent.width
            height: Core.Theme.dp(4)
            radius: 2
            color: Core.Theme.primary
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
        }

        Repeater {
            model: Math.max(0, root.tickCount)
            delegate: Rectangle {
                width: Core.Theme.dp(2)
                height: Core.Theme.dp(index % 2 === 0 ? 10 : 7)
                radius: 1
                color: Core.Theme.mode === "dark" ? "#A8A3C7" : "#667085"
                opacity: 0.75
                x: root.tickCount <= 1 ? 0 : index * (parent.width - width) / (root.tickCount - 1)
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            }
        }
    }

    Rectangle {
        id: handle
        x: Math.round(root.visualPosition * Math.max(0, root.width - width))
        y: Math.round((root.height - height) / 2)
        width: Core.Theme.dp(20)
        height: Core.Theme.dp(20)
        radius: width / 2
        color: Core.Theme.primary
        border.color: Core.Theme.color.card
        border.width: 2
        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
        Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
    }

    Item {
        id: dragProxy
        visible: false
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        propagateComposedEvents: false
        drag.target: dragProxy
        drag.axis: Drag.XAxis
        drag.minimumX: -root.width
        drag.maximumX: root.width * 2
        onPressed: function(mouse) {
            root.dragging = true
            mouse.accepted = true
            root.setValueFromX(mouse.x, true)
        }
        onPositionChanged: function(mouse) {
            if (root.dragging) {
                mouse.accepted = true
                root.setValueFromX(mouse.x, true)
            }
        }
        onReleased: function(mouse) {
            root.dragging = false
            mouse.accepted = true
            root.committed()
        }
        onCanceled: {
            root.dragging = false
            root.committed()
        }
    }
}
