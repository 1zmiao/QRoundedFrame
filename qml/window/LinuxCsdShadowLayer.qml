import QtQuick

Item {
    id: root

    property real shadowInset: 0
    property real shadowOpacity: 1.0
    property int cornerRadius: 0
    property url shadowSource: ""
    property bool shadowVisible: false

    anchors.fill: parent
    anchors.margins: -shadowInset
    visible: shadowVisible
    opacity: shadowOpacity
    z: 0

    readonly property int sourceSize: 160
    readonly property int innerRadiusBias: Qt.platform.os === "linux" ? 2 : 0
    readonly property int c: Math.min(sourceSize / 2, shadowInset + cornerRadius + innerRadiusBias)
    readonly property int centerSize: Math.max(1, sourceSize - c * 2)

    Image {
        x: 0; y: 0; width: root.c; height: root.c
        source: root.shadowSource
        sourceClipRect: Qt.rect(0, 0, root.c, root.c)
        fillMode: Image.Stretch
        smooth: false
        cache: false
    }
    Image {
        x: root.c; y: 0
        width: Math.max(0, root.width - root.c * 2)
        height: root.shadowInset
        source: root.shadowSource
        sourceClipRect: Qt.rect(root.c, 0, root.centerSize, root.shadowInset)
        fillMode: Image.Stretch
        smooth: false
        cache: false
    }
    Image {
        x: root.width - root.c; y: 0
        width: root.c; height: root.c
        source: root.shadowSource
        sourceClipRect: Qt.rect(root.sourceSize - root.c, 0, root.c, root.c)
        fillMode: Image.Stretch
        smooth: false
        cache: false
    }
    Image {
        x: 0; y: root.c
        width: root.shadowInset
        height: Math.max(0, root.height - root.c * 2)
        source: root.shadowSource
        sourceClipRect: Qt.rect(0, root.c, root.shadowInset, root.centerSize)
        fillMode: Image.Stretch
        smooth: false
        cache: false
    }
    Image {
        x: root.width - root.shadowInset; y: root.c
        width: root.shadowInset
        height: Math.max(0, root.height - root.c * 2)
        source: root.shadowSource
        sourceClipRect: Qt.rect(root.sourceSize - root.shadowInset, root.c, root.shadowInset, root.centerSize)
        fillMode: Image.Stretch
        smooth: false
        cache: false
    }
    Image {
        x: 0; y: root.height - root.c
        width: root.c; height: root.c
        source: root.shadowSource
        sourceClipRect: Qt.rect(0, root.sourceSize - root.c, root.c, root.c)
        fillMode: Image.Stretch
        smooth: false
        cache: false
    }
    Image {
        x: root.c; y: root.height - root.shadowInset
        width: Math.max(0, root.width - root.c * 2)
        height: root.shadowInset
        source: root.shadowSource
        sourceClipRect: Qt.rect(root.c, root.sourceSize - root.shadowInset, root.centerSize, root.shadowInset)
        fillMode: Image.Stretch
        smooth: false
        cache: false
    }
    Image {
        x: root.width - root.c
        y: root.height - root.c
        width: root.c; height: root.c
        source: root.shadowSource
        sourceClipRect: Qt.rect(root.sourceSize - root.c, root.sourceSize - root.c, root.c, root.c)
        fillMode: Image.Stretch
        smooth: false
        cache: false
    }
}
