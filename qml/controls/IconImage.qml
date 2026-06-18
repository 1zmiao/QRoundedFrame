import QtQuick
import "../core" as Core

Image {
    id: root

    property string iconName: ""
    property color iconColor: Core.Theme.color.icon
    property real strokeWidth: 1.05
    property string iconVariant: ""

    function autoVariant() {
        if (root.iconVariant === "light" || root.iconVariant === "dark")
            return root.iconVariant
        return Core.Theme.mode === "dark" ? "dark" : "light"
    }

    function safeName() {
        return root.iconName.length > 0 ? root.iconName : "about"
    }

    source: "../../resources/icons/ui/" + autoVariant() + "/" + safeName() + ".png"
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: false
    cache: true
}

