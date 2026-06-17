import QtQuick
import "../core" as Core
import "../controls"

Item {
    id: root

    property string taskType: "default"
    readonly property int inlineCardPadding: Core.Theme.dp(10)
    readonly property var taskTypeValues: ["default", "download", "script"]
    readonly property var taskTypeLabels: ["通用", "导入/下载", "脚本处理"]

    function taskTypeLabel(value) {
        if (value === "download")
            return "导入/下载"
        if (value === "script")
            return "脚本处理"
        return "通用"
    }

    function openTypeMenu(target) {
        target.open()
    }

    function taskTypeIndex(value) {
        const index = taskTypeValues.indexOf(value)
        return index >= 0 ? index : 0
    }

    function typeParams() {
        return typeFieldsLoader.item && typeFieldsLoader.item.params ? typeFieldsLoader.item.params() : ({})
    }

    function createTask() {
        if (typeof App === "undefined" || !App || !App.taskStore)
            return
        App.taskStore.createTask({
            "taskType": taskType,
            "name": nameInput.text,
            "status": statusInput.text,
            "progress": progressSlider.value,
            "priority": priorityInput.text,
            "duration": durationInput.text,
            "count": batchCountInput.text,
            "params": typeParams()
        })
    }

    function applyParsedTask(data) {
        if (!data)
            return
        taskType = data.taskType || "default"
        nameInput.text = data.name || ""
        statusInput.text = data.status || "待处理"
        progressSlider.value = Number(data.progress || 0)
        priorityInput.text = data.priority || "普通"
        durationInput.text = data.duration || "-"
        const params = data.params || ({})
        Qt.callLater(function() {
            if (typeFieldsLoader.item && typeFieldsLoader.item.applyParams)
                typeFieldsLoader.item.applyParams(params)
        })
    }

    function parseClipboard() {
        if (typeof App === "undefined" || !App || !App.taskStore || !Qt.application.clipboard)
            return
        applyParsedTask(App.taskStore.parseClipboardTask(Qt.application.clipboard.text))
    }

    DragScrollArea {
        anchors.fill: parent
        spacing: Core.Theme.dp(12)

        Rectangle {
            width: parent.width
            height: Math.max(Core.Theme.dp(420), form.implicitHeight + root.inlineCardPadding * 2)
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.cardOutline
            border.width: 1
            antialiasing: true
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }

            BackgroundRipple { radius: parent.radius }
            CardAccentGlow { radius: parent.radius }

            Column {
                id: form
                z: 1
                anchors.fill: parent
                anchors.margins: root.inlineCardPadding
                spacing: Core.Theme.dp(10)

                Text {
                    width: parent.width
                    text: "新建任务"
                    color: Core.Theme.color.text
                    font.pixelSize: Core.Theme.fontSize.title
                    font.family: Core.Theme.headingFontFamily
                    font.weight: Core.Theme.headingFontWeight
                    elide: Text.ElideRight
                }

                Flow {
                    width: parent.width
                    spacing: Core.Theme.dp(8)
                    Row {
                        height: Core.Theme.metrics.controlHeight
                        spacing: Core.Theme.dp(8)
                        Text {
                            height: parent.height
                            text: "任务类型"
                            color: Core.Theme.color.mutedText
                            font.pixelSize: Core.Theme.fontSize.control
                            verticalAlignment: Text.AlignVCenter
                        }
                        AppSelect {
                            id: taskTypeSelect
                            width: Core.Theme.dp(168)
                            model: root.taskTypeLabels
                            currentIndex: root.taskTypeIndex(root.taskType)
                            onActivated: function(index) { root.taskType = root.taskTypeValues[index] || "default" }
                        }
                    }
                    AppButton { text: "解析剪贴板"; variant: "soft"; onClicked: root.parseClipboard() }
                }

                AppTextField { id: nameInput; width: parent.width; placeholderText: "名称"; text: "新建任务"; autoSave: false }
                AppTextField { id: statusInput; width: parent.width; placeholderText: "链接 / URL"; text: "https://example.com/parser/source?id=demo-item"; autoSave: false }

                Loader {
                    id: typeFieldsLoader
                    width: parent.width
                    sourceComponent: root.taskType === "download" ? downloadFields : (root.taskType === "script" ? scriptFields : defaultFields)
                }

                Row {
                    width: parent.width
                    height: Core.Theme.dp(34)
                    spacing: Core.Theme.dp(10)
                    Text { width: Core.Theme.dp(64); height: parent.height; text: "进度"; color: Core.Theme.color.text; font.pixelSize: Core.Theme.fontSize.control; verticalAlignment: Text.AlignVCenter }
                    AppSlider { id: progressSlider; width: Math.max(Core.Theme.dp(180), parent.width - Core.Theme.dp(132)); from: 0; to: 100; stepSize: 1 }
                    Text { width: Core.Theme.dp(48); height: parent.height; text: Math.round(progressSlider.value) + "%"; color: Core.Theme.color.mutedText; font.pixelSize: Core.Theme.fontSize.control; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                }

                AppTextField { id: priorityInput; width: parent.width; placeholderText: "优先级"; text: "普通"; autoSave: false }
                AppTextField { id: durationInput; width: parent.width; placeholderText: "耗时"; text: "-"; autoSave: false }
                AppTextField { id: batchCountInput; width: parent.width; placeholderText: "批量数量（性能测试用，默认 1）"; text: "1"; autoSave: false }

                Flow {
                    width: parent.width
                    spacing: Core.Theme.dp(8)
                    AppButton { text: "创建任务"; variant: "primary"; onClicked: root.createTask() }
                }
            }
        }
    }

    Component {
        id: defaultFields
        Column {
            width: parent ? parent.width : 0
            spacing: Core.Theme.dp(8)
            function params() {
                return { "target": defaultTarget.text, "note": defaultNote.text }
            }
            function applyParams(values) {
                defaultTarget.text = values.target || ""
                defaultNote.text = values.note || ""
            }
            AppTextField { id: defaultTarget; width: parent.width; placeholderText: "执行目标"; autoSave: false }
            AppTextField { id: defaultNote; width: parent.width; placeholderText: "备注"; autoSave: false }
        }
    }

    Component {
        id: downloadFields
        Column {
            width: parent ? parent.width : 0
            spacing: Core.Theme.dp(8)
            function params() {
                return { "source": downloadSource.text, "directory": downloadDirectory.text, "retry": downloadRetry.text }
            }
            function applyParams(values) {
                downloadSource.text = values.source || ""
                downloadDirectory.text = values.directory || ""
                downloadRetry.text = values.retry || "3"
            }
            AppTextField { id: downloadSource; width: parent.width; placeholderText: "来源地址 / URL"; autoSave: false }
            AppTextField { id: downloadDirectory; width: parent.width; placeholderText: "保存目录"; autoSave: false }
            AppTextField { id: downloadRetry; width: parent.width; placeholderText: "重试次数"; text: "3"; autoSave: false }
        }
    }

    Component {
        id: scriptFields
        Column {
            width: parent ? parent.width : 0
            spacing: Core.Theme.dp(8)
            function params() {
                return { "script": scriptPath.text, "arguments": scriptArgs.text, "cwd": scriptCwd.text }
            }
            function applyParams(values) {
                scriptPath.text = values.script || ""
                scriptArgs.text = values.arguments || ""
                scriptCwd.text = values.cwd || ""
            }
            AppTextField { id: scriptPath; width: parent.width; placeholderText: "脚本路径"; autoSave: false }
            AppTextField { id: scriptArgs; width: parent.width; placeholderText: "运行参数"; autoSave: false }
            AppTextField { id: scriptCwd; width: parent.width; placeholderText: "工作目录"; autoSave: false }
        }
    }
}
