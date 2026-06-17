pragma Singleton
import QtQuick

QtObject {
    signal prepareChildRequested(string pageKey, string mode)
    signal openChildRequested(string pageKey, string mode, var props)

    property string hoveredInlineKey: ""
    property string activeInlineKey: ""
    readonly property bool pointerInsideInline: hoveredInlineKey.length > 0

    function setInlineHover(pageKey, inside) {
        const key = String(pageKey || "")
        if (inside) {
            hoveredInlineKey = key
            activeInlineKey = key
        } else if (hoveredInlineKey === key) {
            hoveredInlineKey = ""
        }
    }

    function setActiveInline(pageKey) {
        activeInlineKey = String(pageKey || "")
    }

    function openChild(pageKey, props) {
        openChildRequested(String(pageKey || ""), "auto", props || ({}))
    }

    function prepareChild(pageKey, mode) {
        prepareChildRequested(String(pageKey || ""), String(mode || "auto"))
    }

    function openInline(pageKey, props) {
        openChildRequested(String(pageKey || ""), "inline", props || ({}))
    }

    function openNative(pageKey, props) {
        openChildRequested(String(pageKey || ""), "native", props || ({}))
    }
}
