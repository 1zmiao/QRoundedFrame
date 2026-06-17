import QtQuick
import QtQuick.Controls
import QtQuick.Window
import Qt.labs.platform
import "../core" as Core
import "../controls"

Item {
    id: root

    property bool appReady: typeof App !== "undefined" && App !== null
    property int selectedTaskRow: -1
    property int taskSelectionAnchor: -1
    property var selectedTaskRows: ({})
    property bool taskHorizontalDragActive: false
    property bool columnResizeActive: false
    property int selectedGroupRow: -1
    property int groupSelectionAnchor: -1
    property var selectedGroupRows: ({})
    property int editingGroupRow: -1
    property int draggingGroupRow: -1
    property int groupDropPreviewRow: -1
    property bool groupDragSortActive: false
    property bool taskModelAttached: true
    property int groupPaneWidth: Core.Theme.dp(145)
    readonly property int minGroupPaneWidth: Core.Theme.dp(80)
    readonly property int minTaskPaneWidth: Core.Theme.dp(320)
    readonly property real hairlineWidth: 1
    readonly property color taskGridLineColor: Core.Theme.mode === "dark" ? Core.Theme.alpha(Core.Theme.color.hairline, 0.72) : Core.Theme.color.hairline
    readonly property color listPaneFillColor: "transparent"
    readonly property color activeGroupColor: Core.Theme.mode === "dark" ? Core.Theme.mix(Core.Theme.color.navActive, Qt.lighter(Core.Theme.primary, 1.55), 0.20) : Core.Theme.color.navActive
    readonly property color activeGroupBorderColor: Core.Theme.mode === "dark" ? Core.Theme.alpha(Qt.lighter(Core.Theme.primary, 1.95), 0.46) : Core.Theme.alpha(Core.Theme.primaryStrong, 0.22)
    readonly property color activeTaskColor: Core.Theme.mode === "dark" ? Core.Theme.mix(Core.Theme.color.navActive, Qt.lighter(Core.Theme.primary, 1.55), 0.12) : Core.Theme.color.navActive
    readonly property color activeTaskBorderColor: Core.Theme.mode === "dark" ? Core.Theme.alpha(Qt.lighter(Core.Theme.primary, 1.78), 0.30) : Core.Theme.alpha(Core.Theme.primaryStrong, 0.18)
    readonly property color groupDropPreviewColor: Core.Theme.mode === "dark" ? Core.Theme.alpha(Qt.lighter(Core.Theme.primary, 2.2), 0.92) : Core.Theme.color.outlineAccent
    readonly property int listPaneRadius: Core.Theme.radius.button
    readonly property color splitLineColor: Core.Theme.mode === "dark" ? Core.Theme.alpha(Qt.lighter(Core.Theme.primary, 1.65), 0.88) : Core.Theme.color.outlineAccent
    property bool taskTableLayoutPending: false
    property bool columnWidthsLoaded: false
    property bool groupActivationPending: false
    property var columnWidths: [220, 86, 96, 86, 86, 92, 154]
    property var columnTitles: ["名称", "类型", "链接", "进度", "优先级", "耗时", "更新时间"]
    readonly property bool hasGroups: root.appReady && App.taskStore && App.taskStore.groupCount > 0
    readonly property int groupRowHeight: Core.Theme.dp(40)

    function openCreateTask(taskType) {
        App.prepareOpenChild("task-create", "inline")
        App.requestOpenChild("task-create", "inline", ({ "taskType": taskType || "default" }))
    }

    function openTaskMenu(px, py, row) {
        if (!taskRowSelected(row))
            selectSingleTaskRow(row)
        const taskId = root.appReady && App.taskStore ? App.taskStore.taskIdAt(row) : 0
        taskContextMenu.openForActions([
            { text: "新建任务", action: "new", available: root.hasGroups },
            { text: "编辑任务", action: "edit", available: taskId > 0 },
            { text: "导入 CSV/JSON", action: "import" },
            { text: "删除选中", action: "delete", available: selectedTaskCount() > 0 },
            { text: "刷新分组", action: "refresh" }
        ], px, py)
    }

    function taskRowSelected(row) {
        return selectedTaskRows[row] === true
    }

    function selectedTaskCount() {
        let total = 0
        for (let key in selectedTaskRows) {
            if (selectedTaskRows[key])
                total += 1
        }
        return total
    }

    function selectedTaskRowArray() {
        const rows = []
        for (let key in selectedTaskRows) {
            if (selectedTaskRows[key])
                rows.push(Number(key))
        }
        rows.sort(function(a, b) { return a - b })
        return rows
    }

    function selectSingleTaskRow(row) {
        selectedTaskRow = row
        taskSelectionAnchor = row
        const next = {}
        if (row >= 0)
            next[row] = true
        selectedTaskRows = next
    }

    function selectTaskRange(row) {
        const anchor = taskSelectionAnchor >= 0 ? taskSelectionAnchor : row
        const begin = Math.min(anchor, row)
        const end = Math.max(anchor, row)
        const next = {}
        for (let i = begin; i <= end; ++i)
            next[i] = true
        selectedTaskRow = row
        selectedTaskRows = next
    }

    function toggleTaskRow(row) {
        const next = {}
        for (let key in selectedTaskRows)
            next[key] = selectedTaskRows[key]
        if (next[row])
            delete next[row]
        else
            next[row] = true
        selectedTaskRow = row
        taskSelectionAnchor = row
        selectedTaskRows = next
    }

    function openGroupMenu(px, py, row) {
        if (row >= 0 && !groupRowSelected(row))
            selectSingleGroupRow(row)
        else if (row < 0)
            selectedGroupRow = -1
        taskContextMenu.openForActions([
            { text: "新建分组", action: "group-new" },
            { text: "重命名分组", action: "group-rename", available: row >= 0 },
            { text: "删除选中分组", action: "group-delete", available: groupSelectionCount() > 0 },
            { text: "刷新分组", action: "refresh" }
        ], px, py)
    }

    function groupRowSelected(row) {
        return selectedGroupRows[row] === true
    }

    function groupSelectionCount() {
        let total = 0
        for (let key in selectedGroupRows) {
            if (selectedGroupRows[key])
                total += 1
        }
        return total
    }

    function selectedGroupRowArray() {
        const rows = []
        for (let key in selectedGroupRows) {
            if (selectedGroupRows[key])
                rows.push(Number(key))
        }
        rows.sort(function(a, b) { return a - b })
        return rows
    }

    function selectSingleGroupRow(row) {
        selectedGroupRow = row
        groupSelectionAnchor = row
        const next = {}
        if (row >= 0)
            next[row] = true
        selectedGroupRows = next
    }

    function selectGroupRange(row) {
        const anchor = groupSelectionAnchor >= 0 ? groupSelectionAnchor : row
        const begin = Math.min(anchor, row)
        const end = Math.max(anchor, row)
        const next = {}
        for (let i = begin; i <= end; ++i)
            next[i] = true
        selectedGroupRow = row
        selectedGroupRows = next
    }

    function toggleGroupRow(row) {
        const next = {}
        for (let key in selectedGroupRows)
            next[key] = selectedGroupRows[key]
        if (next[row])
            delete next[row]
        else
            next[row] = true
        selectedGroupRow = row
        groupSelectionAnchor = row
        selectedGroupRows = next
    }

    function clearTaskSelection() {
        selectedTaskRow = -1
        taskSelectionAnchor = -1
        selectedTaskRows = ({})
    }

    function clearGroupSelection() {
        selectedGroupRow = -1
        groupSelectionAnchor = -1
        selectedGroupRows = ({})
    }

    function activateGroup(index) {
        if (!root.appReady || !App.taskStore || index < 0)
            return
        root.clearTaskSelection()
        root.taskHorizontalDragActive = false
        root.taskModelAttached = false
        if (taskTable) {
            if (taskTable.cancelFlick)
                taskTable.cancelFlick()
            taskTable.contentX = 0
            taskTable.contentY = 0
        }
        App.taskStore.selectGroup(index)
        root.requestTaskTableLayout()
        root.groupActivationPending = true
        groupActivationTimer.restart()
    }

    function syncGroupListCurrentIndex() {
        if (!root.appReady || !App.taskStore || !groupList)
            return
        const nextIndex = App.taskStore.currentGroupIndex
        if (nextIndex >= 0 && nextIndex < groupList.count && groupList.currentIndex !== nextIndex)
            groupList.currentIndex = nextIndex
        if (nextIndex >= 0 && nextIndex < groupList.count && root.groupSelectionCount() === 0)
            root.selectSingleGroupRow(nextIndex)
    }

    function requestGroupListSync() {
        syncGroupTimer.restart()
    }

    function finishGroupRename(commitChanges) {
        if (root.editingGroupRow < 0 || !root.appReady || !App.taskStore)
            return
        const row = root.editingGroupRow
        root.editingGroupRow = -1
        if (commitChanges && groupList && row >= 0 && row < groupList.count) {
            const item = groupList.itemAtIndex(row)
            if (item && item.renameText !== undefined && item.renameText !== item.groupName)
                App.taskStore.renameGroupAt(row, item.renameText)
        }
    }

    function taskCellText(column, name, taskType, status, progress, priority, duration, updatedAt) {
        if (column === 0)
            return name
        if (column === 1)
            return taskTypeLabel(taskType)
        if (column === 2)
            return status
        if (column === 3)
            return Number(progress) + "%"
        if (column === 4)
            return priority
        if (column === 5)
            return duration
        if (column === 6)
            return updatedAt
        return ""
    }

    function taskTypeLabel(value) {
        if (value === "download")
            return "导入/下载"
        if (value === "script")
            return "脚本处理"
        return "通用"
    }

    function resolvedTaskColumnWidth(column, tableWidth) {
        if (column === columnTitles.length - 1) {
            let used = 0
            for (let i = 0; i < columnTitles.length - 1; ++i)
                used += Core.Theme.dp(columnWidths[i] || 120)
            return Math.max(Core.Theme.dp(columnWidths[column] || 154), tableWidth - used)
        }
        return Core.Theme.dp(columnWidths[column] || 120)
    }

    function setTaskColumnWidth(column, widthPx, immediate) {
        if (column >= columnTitles.length - 1)
            return
        const next = columnWidths.slice()
        next[column] = Math.max(64, Math.round(widthPx / Core.Theme.dp(1)))
        columnWidths = next
        requestTaskTableLayout()
        taskColumnSaveTimer.restart()
    }

    function loadTaskColumnWidths() {
        if (columnWidthsLoaded || !root.appReady || !App.settings)
            return
        columnWidthsLoaded = true
        const saved = App.settings.valueOr("taskList/columnWidths", [])
        if (!saved || saved.length !== columnWidths.length)
            return
        const next = columnWidths.slice()
        for (let i = 0; i < saved.length; ++i) {
            const value = Number(saved[i])
            if (isFinite(value))
                next[i] = Math.max(64, Math.min(720, Math.round(value)))
        }
        columnWidths = next
        requestTaskTableLayout()
    }

    function saveTaskColumnWidths() {
        if (!root.appReady || !App.settings)
            return
        const next = []
        for (let i = 0; i < columnWidths.length; ++i)
            next.push(Math.max(64, Math.round(Number(columnWidths[i]) || 120)))
        App.settings.setValue("taskList/columnWidths", next)
    }

    function loadTaskPaneLayout() {
        if (!root.appReady || !App.settings)
            return
        const savedWidth = Number(App.settings.valueOr("taskList/groupPaneWidth", root.groupPaneWidth))
        if (isFinite(savedWidth))
            root.groupPaneWidth = Math.max(root.minGroupPaneWidth, Math.min(Math.round(savedWidth), Math.max(root.minGroupPaneWidth, root.width - root.minTaskPaneWidth)))
    }

    function saveTaskPaneLayout() {
        if (!root.appReady || !App.settings)
            return
        App.settings.setValue("taskList/groupPaneWidth", Math.round(root.groupPaneWidth))
    }

    function requestTaskTableLayout() {
        if (taskTableLayoutPending)
            return
        taskTableLayoutPending = true
        taskTableLayoutTimer.restart()
    }

    function applyTaskTableColumnWidths() {
        if (!taskTable || !taskTable.setColumnWidth)
            return
        for (let i = 0; i < columnTitles.length; ++i)
            taskTable.setColumnWidth(i, root.resolvedTaskColumnWidth(i, taskTable.width))
    }

    function taskTableContentWidth(tableWidth) {
        let total = 0
        for (let i = 0; i < columnTitles.length; ++i)
            total += root.resolvedTaskColumnWidth(i, tableWidth)
        return total
    }

    FileDialog {
        id: importDialog
        title: "导入任务列表"
        nameFilters: ["CSV/JSON 文件 (*.csv *.json)", "所有文件 (*)"]
        onAccepted: {
            if (root.appReady && App.taskStore)
                App.taskStore.importFile(String(file))
        }
    }

    Connections {
        target: root.appReady && App.taskStore ? App.taskStore : null
        function onGroupChanged() {
            root.requestGroupListSync()
        }
    }

    AppContextMenu {
        id: taskContextMenu
        anchors.fill: parent
        onActionTriggered: function(action) {
            if (!root.appReady || !App.taskStore)
                return
            if (action === "new" && root.hasGroups)
                root.openCreateTask("default")
            else if (action === "edit") {
                const taskId = App.taskStore.taskIdAt(root.selectedTaskRow)
                if (taskId > 0) {
                    App.prepareOpenChild("task-edit", "inline")
                    App.requestOpenChild("task-edit", "inline", ({ "taskId": taskId, "taskType": App.taskStore.taskTypeAt(root.selectedTaskRow) }))
                }
            }
            else if (action === "import")
                importDialog.open()
            else if (action === "delete")
            {
                App.taskStore.deleteTaskRows(root.selectedTaskRowArray())
                root.clearTaskSelection()
            }
            else if (action === "group-new")
                App.taskStore.addGroup()
            else if (action === "group-rename")
                root.editingGroupRow = root.selectedGroupRow
            else if (action === "group-delete")
            {
                App.taskStore.deleteGroupRows(root.selectedGroupRowArray())
                root.clearGroupSelection()
            }
            else if (action === "refresh")
                App.taskStore.refresh()
        }
    }

    Timer {
        id: taskTableLayoutTimer
        interval: 16
        repeat: false
        onTriggered: {
            root.taskTableLayoutPending = false
            if (root.appReady && typeof root.applyTaskTableColumnWidths === "function")
                root.applyTaskTableColumnWidths()
        }
    }

    Timer {
        id: taskColumnSaveTimer
        interval: 260
        repeat: false
        onTriggered: root.saveTaskColumnWidths()
    }

    Timer {
        id: taskPaneLayoutSaveTimer
        interval: 260
        repeat: false
        onTriggered: root.saveTaskPaneLayout()
    }

    Timer {
        id: syncGroupTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (root.appReady && typeof root.syncGroupListCurrentIndex === "function")
                root.syncGroupListCurrentIndex()
        }
    }

    Timer {
        id: groupActivationTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (!root.appReady || !root.groupActivationPending)
                return
            root.groupActivationPending = false
            root.taskModelAttached = true
            if (taskTable) {
                taskTable.contentX = 0
                taskTable.contentY = 0
            }
            root.requestTaskTableLayout()
        }
    }

    Component.onCompleted: {
        root.loadTaskColumnWidths()
        root.loadTaskPaneLayout()
    }

    DragScrollArea {
        id: toolsScrollArea
        anchors.fill: parent
        spacing: Core.Theme.metrics.spacing
        scrollLocked: root.groupDragSortActive

        Rectangle {
            width: parent.width
            height: Math.max(Core.Theme.dp(142), toolContent.implicitHeight + Core.Theme.metrics.cardHeightPadding)
            radius: Core.Theme.radius.card
            color: Core.Theme.color.hero
            border.color: Core.Theme.color.cardOutline
            Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            antialiasing: true

            BackgroundRipple { radius: parent.radius }
            CardAccentGlow { radius: parent.radius }

            Column {
                id: toolContent
                z: 1
                anchors.fill: parent
                anchors.margins: Core.Theme.metrics.cardPadding
                spacing: Core.Theme.dp(10)

                Text {
                    text: "工具"
                    color: Core.Theme.color.text
                    font.pixelSize: Core.Theme.fontSize.title
                    font.family: Core.Theme.headingFontFamily
                    font.weight: Core.Theme.headingFontWeight
                    font.letterSpacing: Core.Theme.headingLetterSpacing
                }

                Text {
                    width: parent.width
                    text: "这里可以放置项目专属工具。重任务列表使用模型虚拟化和 SQLite 后台导入，避免一次性创建大量 QML 对象。"
                    color: Core.Theme.color.mutedText
                    font.pixelSize: Core.Theme.fontSize.body
                    wrapMode: Text.WordWrap
                    lineHeight: Core.Theme.bodyLineHeight
                }

                Flow {
                    width: parent.width
                    spacing: Core.Theme.dp(8)
                    AppButton { text: "工具操作"; variant: "primary" }
                    AppButton {
                        text: "打开页内子窗口"
                        variant: "soft"
                        onPressStarted: App.prepareOpenChild("inline-demo", "inline")
                        onClicked: App.requestOpenChild("inline-demo", "inline", ({}))
                    }
                    AppButton {
                        text: "打开关于子窗口"
                        outlineGhost: true
                        onPressStarted: App.prepareOpenChild("about", "native")
                        onClicked: App.requestOpenChild("about", "native", ({}))
                    }
                }
            }
        }

        Rectangle {
            id: taskCard
            width: parent.width
            height: Core.Theme.dp(560)
            radius: Core.Theme.radius.card
            color: Core.Theme.color.card
            border.color: Core.Theme.color.cardOutline
            clip: true
            Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
            antialiasing: true

            BackgroundRipple { radius: parent.radius }
            CardAccentGlow { radius: parent.radius }

            Column {
                id: taskPanel
                z: 1
                anchors.fill: parent
                anchors.margins: 0
                spacing: Core.Theme.dp(4)

                Row {
                    x: Core.Theme.metrics.cardPadding
                    width: Math.max(1, parent.width - Core.Theme.metrics.cardPadding * 2)
                    height: Core.Theme.metrics.controlHeight + Core.Theme.dp(8)
                    spacing: Core.Theme.dp(8)

                    Text {
                        width: Math.max(Core.Theme.dp(160), parent.width - statusText.width - importButton.width - addButton.width - refreshButton.width - Core.Theme.dp(40))
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: Core.Theme.dp(3)
                        text: "重任务列表"
                        color: Core.Theme.color.text
                        font.pixelSize: Core.Theme.fontSize.subtitle
                        font.family: Core.Theme.headingFontFamily
                        font.weight: Core.Theme.headingFontWeight
                        elide: Text.ElideRight
                    }

                    Text {
                        id: statusText
                        width: Math.min(Core.Theme.dp(220), Math.max(Core.Theme.dp(80), implicitWidth))
                        height: Core.Theme.metrics.controlHeight
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: Core.Theme.dp(3)
                        text: root.appReady && App.taskStore ? App.taskStore.statusMessage : ""
                        color: Core.Theme.color.mutedText
                        font.pixelSize: Core.Theme.fontSize.caption
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    AppButton { id: importButton; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: Core.Theme.dp(3); text: "导入"; variant: "soft"; onClicked: importDialog.open() }
                    AppButton { id: addButton; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: Core.Theme.dp(3); text: "新建"; variant: "primary"; enabled: root.hasGroups; onClicked: root.openCreateTask("default") }
                    AppButton { id: refreshButton; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: Core.Theme.dp(3); text: "刷新"; outlineGhost: true; onClicked: App.taskStore.refresh() }
                }

                Item {
                    id: taskListSurface
                    width: parent.width
                    height: Math.max(Core.Theme.dp(1), taskPanel.height - y)

                    Rectangle {
                        id: groupPane
                        width: Math.max(root.minGroupPaneWidth, Math.min(root.groupPaneWidth, parent.width - root.minTaskPaneWidth))
                        height: parent.height
                        radius: root.listPaneRadius
                        color: root.listPaneFillColor
                        border.color: "transparent"
                        border.width: 0
                        clip: true
                        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }

                        Rectangle {
                            anchors.fill: parent
                            radius: root.listPaneRadius
                            color: root.listPaneFillColor
                            z: 0
                            visible: false
                            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: root.listPaneRadius
                            color: root.listPaneFillColor
                            z: 1
                            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: root.listPaneRadius
                            width: root.hairlineWidth
                            color: Core.Theme.color.outline
                            z: 3
                            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: root.hairlineWidth
                            color: Core.Theme.color.outline
                            z: 3
                            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                        }
                        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: root.hairlineWidth; color: Core.Theme.color.outline; z: 3; visible: false }

                        ListView {
                            id: groupList
                            z: 2
                            anchors.fill: parent
                            anchors.margins: Core.Theme.dp(6)
                            clip: true
                            model: root.appReady && App.taskStore ? App.taskStore.groupModel : null
                            currentIndex: root.appReady && App.taskStore ? App.taskStore.currentGroupIndex : 0
                            Component.onCompleted: root.requestGroupListSync()
                            onModelChanged: root.requestGroupListSync()
                            onCountChanged: root.requestGroupListSync()
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar {
                                id: groupScrollBar
                                policy: ScrollBar.AsNeeded
                                visible: groupList.contentHeight > groupList.height + Core.Theme.dp(1)
                                anchors.right: parent.right
                                anchors.rightMargin: Core.Theme.dp(1)
                                width: Core.Theme.dp(11)
                                contentItem: Rectangle {
                                    implicitWidth: Core.Theme.dp(10)
                                    radius: width / 2
                                    opacity: (groupScrollBar.active || groupScrollBar.hovered || groupScrollBar.pressed) ? 0.86 : 0
                                    color: groupScrollBar.pressed ? Core.Theme.primaryPressed : (groupScrollBar.hovered ? Core.Theme.primaryHover : Core.Theme.color.outline)
                                    Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                                }
                                background: Item { implicitWidth: Core.Theme.dp(11) }
                            }
                            delegate: Item {
                                width: groupList.width
                                height: root.groupRowHeight
                                property bool selected: index === groupList.currentIndex
                                property string groupName: name
                                property string renameText: groupNameEditor.text
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.topMargin: Core.Theme.dp(1)
                                    anchors.bottomMargin: Core.Theme.dp(1)
                                    radius: Core.Theme.radius.button
                                    color: root.groupRowSelected(index) ? root.activeGroupColor : (groupMouse.containsMouse ? Core.Theme.color.controlHover : Core.Theme.alpha(Core.Theme.color.controlHover, 0))
                                    border.width: root.groupRowSelected(index) ? 1 : 0
                                    border.color: root.activeGroupBorderColor
                                    Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Core.Theme.dp(5)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.groupRowSelected(index) ? Core.Theme.dp(3) : Core.Theme.dp(2)
                                    height: root.groupRowSelected(index) ? Core.Theme.dp(22) : Core.Theme.dp(14)
                                    radius: width / 2
                                    color: root.groupRowSelected(index)
                                           ? (Core.Theme.mode === "dark" ? Qt.lighter(Core.Theme.primary, 1.95) : Core.Theme.primary)
                                           : (Core.Theme.mode === "dark"
                                              ? Core.Theme.alpha(Qt.lighter(Core.Theme.primary, 1.65), groupMouse.containsMouse ? 0.62 : 0.40)
                                              : Core.Theme.alpha(Core.Theme.primary, groupMouse.containsMouse ? 0.46 : 0.28))
                                    opacity: root.groupRowSelected(index) || groupMouse.containsMouse ? 1.0 : 0.72
                                    Behavior on width { NumberAnimation { duration: Core.Theme.controlTransitionMs; easing.type: Easing.OutCubic } }
                                    Behavior on height { NumberAnimation { duration: Core.Theme.controlTransitionMs; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                                    Behavior on opacity { NumberAnimation { duration: Core.Theme.controlTransitionMs; easing.type: Easing.OutCubic } }
                                }

                                Text {
                                    visible: root.editingGroupRow !== index
                                    anchors.left: parent.left
                                    anchors.leftMargin: Core.Theme.dp(14)
                                    anchors.right: groupCountText.visible ? groupCountText.left : parent.right
                                    anchors.rightMargin: Core.Theme.dp(4)
                                    anchors.verticalCenter: parent.verticalCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: name
                                    color: root.groupRowSelected(index) ? Core.Theme.color.navSelectedText : Core.Theme.color.text
                                    font.pixelSize: Core.Theme.fontSize.control
                                    elide: Text.ElideRight
                                }

                                AppTextField {
                                    id: groupNameEditor
                                    visible: root.editingGroupRow === index
                                    anchors.left: parent.left
                                    anchors.leftMargin: Core.Theme.dp(14)
                                    anchors.right: groupCountText.visible ? groupCountText.left : parent.right
                                    anchors.rightMargin: Core.Theme.dp(4)
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: Core.Theme.dp(28)
                                    text: name
                                    autoSave: false
                                    floatingPlaceholder: false

                                    function commit() {
                                        root.finishGroupRename(true)
                                    }

                                    onAccepted: commit()
                                    onEditingFinished: commit()
                                    onVisibleChanged: {
                                        if (visible)
                                            Qt.callLater(function() { groupNameEditor.forceActiveFocus() })
                                    }
                                }

                                Text {
                                    id: groupCountText
                                    visible: groupList.width >= Core.Theme.dp(78)
                                    anchors.right: parent.right
                                    anchors.rightMargin: Core.Theme.dp(6)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(Core.Theme.dp(24), Math.max(Core.Theme.dp(12), implicitWidth))
                                    horizontalAlignment: Text.AlignRight
                                    text: count
                                    color: root.groupRowSelected(index) ? Core.Theme.color.navSelectedText : Core.Theme.color.mutedText
                                    opacity: root.groupRowSelected(index) ? 0.78 : 0.58
                                    font.pixelSize: Core.Theme.fontSize.tiny
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.leftMargin: Core.Theme.dp(6)
                                    anchors.rightMargin: Core.Theme.dp(6)
                                    height: 2
                                    radius: 1
                                    visible: root.groupDragSortActive && root.groupDropPreviewRow === index
                                    color: root.groupDropPreviewColor
                                    z: 4
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: Core.Theme.dp(6)
                                    anchors.rightMargin: Core.Theme.dp(6)
                                    height: 2
                                    radius: 1
                                    visible: root.groupDragSortActive && index === groupList.count - 1 && root.groupDropPreviewRow === groupList.count
                                    color: root.groupDropPreviewColor
                                    z: 4
                                }

                                MouseArea {
                                    id: groupMouse
                                    anchors.fill: parent
                                    enabled: root.editingGroupRow !== index
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    preventStealing: true
                                    property real pressX: 0
                                    property real pressY: 0
                                    onPressed: function(mouse) {
                                        if (mouse.button === Qt.RightButton) {
                                            groupList.currentIndex = index
                                            root.activateGroup(index)
                                            const p = mapToItem(root, mouse.x, mouse.y)
                                            root.openGroupMenu(p.x, p.y, index)
                                            mouse.accepted = true
                                            return
                                        }
                                        if (mouse.modifiers & Qt.ShiftModifier)
                                            root.selectGroupRange(index)
                                        else if (mouse.modifiers & Qt.ControlModifier)
                                            root.toggleGroupRow(index)
                                        else
                                            root.selectSingleGroupRow(index)
                                        groupList.currentIndex = index
                                        root.activateGroup(index)
                                        root.draggingGroupRow = index
                                        root.groupDropPreviewRow = -1
                                        root.groupDragSortActive = false
                                        pressX = mouse.x
                                        pressY = mouse.y
                                        mouse.accepted = true
                                    }
                                    onPositionChanged: function(mouse) {
                                        if (!pressed || root.draggingGroupRow < 0)
                                            return
                                        const dx = mouse.x - pressX
                                        const dy = mouse.y - pressY
                                        const threshold = Core.Theme.dp(7)
                                        if (!root.groupDragSortActive) {
                                            if (Math.abs(dx) < threshold && Math.abs(dy) < threshold)
                                                return
                                            root.groupDragSortActive = true
                                        }
                                        const p = mapToItem(groupList, mouse.x, mouse.y)
                                        const rawTarget = Math.floor((p.y + groupList.contentY) / root.groupRowHeight)
                                        root.groupDropPreviewRow = Math.max(0, Math.min(groupList.count, rawTarget))
                                    }
                                    onReleased: {
                                        if (root.groupDragSortActive && root.draggingGroupRow >= 0 && root.groupDropPreviewRow >= 0) {
                                            const target = Math.max(0, Math.min(groupList.count - 1, root.groupDropPreviewRow))
                                            if (target !== root.draggingGroupRow) {
                                                App.taskStore.moveGroup(root.draggingGroupRow, target)
                                                root.selectSingleGroupRow(target)
                                                groupList.currentIndex = target
                                            }
                                        }
                                        root.draggingGroupRow = -1
                                        root.groupDropPreviewRow = -1
                                        root.groupDragSortActive = false
                                    }
                                    onCanceled: {
                                        root.draggingGroupRow = -1
                                        root.groupDropPreviewRow = -1
                                        root.groupDragSortActive = false
                                    }
                                    onDoubleClicked: function(mouse) {
                                        root.editingGroupRow = index
                                        mouse.accepted = true
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: Core.Theme.dp(6)
                            acceptedButtons: Qt.RightButton
                            z: 1
                            onPressed: function(mouse) {
                                const p = mapToItem(root, mouse.x, mouse.y)
                                root.openGroupMenu(p.x, p.y, -1)
                                mouse.accepted = true
                            }
                        }
                    }

                    Item {
                        id: splitHandle
                        anchors.left: groupPane.right
                        width: root.hairlineWidth
                        height: parent.height

                        Rectangle {
                            anchors.fill: parent
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: root.hairlineWidth
                            radius: root.hairlineWidth / 2
                            color: root.splitLineColor
                            opacity: splitMouse.containsMouse || splitMouse.pressed ? 1.0 : 0.82
                        }

                        MouseArea {
                            id: splitMouse
                            anchors.fill: parent
                            anchors.leftMargin: -Core.Theme.dp(6)
                            anchors.rightMargin: -Core.Theme.dp(6)
                            hoverEnabled: true
                            cursorShape: Qt.SplitHCursor
                            preventStealing: true
                            property real pressGlobalX: 0
                            property int startWidth: 0
                            onPressed: function(mouse) {
                                root.editingGroupRow = -1
                                pressGlobalX = splitHandle.mapToItem(splitHandle.parent, mouse.x, mouse.y).x
                                startWidth = root.groupPaneWidth
                                mouse.accepted = true
                            }
                            onPositionChanged: function(mouse) {
                                if (!pressed)
                                    return
                                const dx = splitHandle.mapToItem(splitHandle.parent, mouse.x, mouse.y).x - pressGlobalX
                                root.groupPaneWidth = Math.max(root.minGroupPaneWidth, Math.min(startWidth + dx, splitHandle.parent.width - root.minTaskPaneWidth))
                                taskPaneLayoutSaveTimer.restart()
                                mouse.accepted = true
                            }
                        }
                    }

                    Rectangle {
                        id: taskPane
                        anchors.left: splitHandle.right
                        width: Math.max(1, parent.width - x)
                        height: parent.height
                        radius: root.listPaneRadius
                        color: root.listPaneFillColor
                        border.color: "transparent"
                        border.width: 0
                        clip: true
                        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }

                        Rectangle {
                            anchors.fill: parent
                            radius: root.listPaneRadius
                            color: root.listPaneFillColor
                            z: 0
                            visible: false
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: root.listPaneRadius
                            color: root.listPaneFillColor
                            z: 1
                            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                        }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: root.listPaneRadius
                            width: root.hairlineWidth
                            color: Core.Theme.color.outline
                            z: 3
                            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                        }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: root.hairlineWidth
                            color: Core.Theme.color.outline
                            z: 3
                            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.rightMargin: root.listPaneRadius
                            anchors.bottom: parent.bottom
                            height: root.hairlineWidth
                            color: Core.Theme.color.outline
                            z: 3
                            Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                        }

                        Column {
                            z: 2
                            anchors.fill: parent
                            anchors.margins: root.hairlineWidth
                            clip: true

                            Item {
                                id: headerClip
                                width: parent.width
                                height: Core.Theme.dp(34)
                                clip: true

                                Row {
                                    id: headerRow
                                    x: -taskTable.contentX
                                    width: root.taskTableContentWidth(taskTable.width)
                                    height: parent.height

                                    Repeater {
                                        model: root.columnTitles.length
                                        delegate: Rectangle {
                                            width: root.resolvedTaskColumnWidth(index, taskTable.width)
                                            height: parent.height
                                            radius: 0
                                            color: "transparent"
                                            clip: true
                                            Rectangle {
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
                                                width: root.hairlineWidth
                                                visible: index < root.columnTitles.length - 1
                                                color: root.taskGridLineColor
                                                Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                color: Core.Theme.color.cardAlt
                                                Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                                            }

                                            Text {
                                                anchors.fill: parent
                                                anchors.leftMargin: Core.Theme.dp(8)
                                                anchors.rightMargin: Core.Theme.dp(8)
                                                verticalAlignment: Text.AlignVCenter
                                                text: root.columnTitles[index]
                                                color: Core.Theme.color.text
                                                font.pixelSize: Core.Theme.fontSize.caption
                                                font.family: Core.Theme.headingFontFamily
                                                elide: Text.ElideRight
                                            }

                                            Rectangle {
                                                id: columnResizeLine
                                                anchors.right: parent.right
                                                width: root.hairlineWidth
                                                height: parent.height
                                                visible: index < root.columnTitles.length - 1
                                                color: columnResizeMouse.containsMouse || columnResizeMouse.pressed ? Core.Theme.color.outline : root.taskGridLineColor
                                                Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                                            }

                                            MouseArea {
                                                id: columnResizeMouse
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
                                                width: Core.Theme.dp(10)
                                                visible: index < root.columnTitles.length - 1
                                                enabled: visible
                                                hoverEnabled: true
                                                cursorShape: Qt.SplitHCursor
                                                preventStealing: true
                                                property real pressSceneX: 0
                                                property real startWidth: 0
                                                onPressed: function(mouse) {
                                                    pressSceneX = mapToItem(root, mouse.x, mouse.y).x
                                                    startWidth = parent.width
                                                    root.columnResizeActive = true
                                                    mouse.accepted = true
                                                }
                                                onPositionChanged: function(mouse) {
                                                    if (!pressed)
                                                        return
                                                    const sceneX = mapToItem(root, mouse.x, mouse.y).x
                                                    const nextWidth = Math.max(Core.Theme.dp(64), startWidth + sceneX - pressSceneX)
                                                    root.setTaskColumnWidth(index, nextWidth, true)
                                                    mouse.accepted = true
                                                }
                                                onReleased: function(mouse) {
                                                    const sceneX = mapToItem(root, mouse.x, mouse.y).x
                                                    root.columnResizeActive = false
                                                    root.setTaskColumnWidth(index, startWidth + sceneX - pressSceneX, true)
                                                    mouse.accepted = true
                                                }
                                                onCanceled: root.columnResizeActive = false
                                            }
                                        }
                                    }
                                }
                            }

                            TableView {
                                id: taskTable
                                width: parent.width
                                height: Math.max(1, parent.height - headerClip.height)
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                reuseItems: true
                                model: root.taskModelAttached && root.appReady && App.taskStore ? App.taskStore.taskModel : null
                                rowHeightProvider: function(row) { return Core.Theme.dp(34) }
                                ScrollBar.vertical: ScrollBar {
                                    id: taskScrollBar
                                    policy: ScrollBar.AsNeeded
                                    visible: taskTable.contentHeight > taskTable.height + Core.Theme.dp(1)
                                    anchors.right: parent.right
                                    anchors.rightMargin: Core.Theme.dp(1)
                                    width: Core.Theme.dp(11)
                                    contentItem: Rectangle {
                                        implicitWidth: Core.Theme.dp(10)
                                        radius: width / 2
                                        opacity: (taskScrollBar.active || taskScrollBar.hovered || taskScrollBar.pressed) ? 0.86 : 0
                                        color: taskScrollBar.pressed ? Core.Theme.primaryPressed : (taskScrollBar.hovered ? Core.Theme.primaryHover : Core.Theme.color.outline)
                                        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                                        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                                    }
                                    background: Item { implicitWidth: Core.Theme.dp(11) }
                                }
                                ScrollBar.horizontal: ScrollBar {
                                    id: taskHorizontalScrollBar
                                    policy: ScrollBar.AsNeeded
                                    visible: taskTable.contentWidth > taskTable.width + Core.Theme.dp(1)
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: Core.Theme.dp(1)
                                    height: Core.Theme.dp(11)
                                    contentItem: Rectangle {
                                        implicitHeight: Core.Theme.dp(10)
                                        radius: height / 2
                                        opacity: (taskHorizontalScrollBar.active || taskHorizontalScrollBar.hovered || taskHorizontalScrollBar.pressed) ? 0.86 : 0
                                        color: taskHorizontalScrollBar.pressed ? Core.Theme.primaryPressed : (taskHorizontalScrollBar.hovered ? Core.Theme.primaryHover : Core.Theme.color.outline)
                                        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                                        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                                    }
                                    background: Item { implicitHeight: Core.Theme.dp(11) }
                                }
                                Component.onCompleted: root.requestTaskTableLayout()
                                onWidthChanged: root.requestTaskTableLayout()
                                onModelChanged: {
                                    root.clearTaskSelection()
                                    contentY = 0
                                    root.requestTaskTableLayout()
                                }
                                onContentYChanged: {
                                    if (root.appReady && App.taskStore)
                                        App.taskStore.prefetchAround(Math.max(0, Math.floor(contentY / Core.Theme.dp(34))))
                                }

                                delegate: Rectangle {
                                    implicitWidth: root.resolvedTaskColumnWidth(column, taskTable.width)
                                    implicitHeight: Core.Theme.dp(34)
                                    color: root.taskRowSelected(row) ? root.activeTaskColor : (cellMouse.containsMouse ? Core.Theme.color.controlHover : Core.Theme.alpha(Core.Theme.color.controlHover, 0))
                                    Behavior on color { ColorAnimation { duration: Core.Theme.controlTransitionMs; easing.type: Easing.InOutCubic } }

                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: root.hairlineWidth
                                        visible: column < root.columnTitles.length - 1
                                        color: root.taskGridLineColor
                                        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.rightMargin: column === root.columnTitles.length - 1 ? root.listPaneRadius : 0
                                        anchors.bottom: parent.bottom
                                        height: root.hairlineWidth
                                        color: root.taskGridLineColor
                                        Behavior on color { ColorAnimation { duration: Core.Theme.animatedColorTransitionMs; easing.type: Easing.InOutCubic } }
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.rightMargin: column === root.columnTitles.length - 1 ? root.listPaneRadius : 0
                                        anchors.top: parent.top
                                        height: root.hairlineWidth
                                        visible: root.taskRowSelected(row) && !root.taskRowSelected(row - 1)
                                        color: root.activeTaskBorderColor
                                        opacity: Core.Theme.mode === "dark" ? 1.0 : 0.55
                                        z: 2
                                        Behavior on color { ColorAnimation { duration: Core.Theme.controlTransitionMs; easing.type: Easing.InOutCubic } }
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.rightMargin: column === root.columnTitles.length - 1 ? root.listPaneRadius : 0
                                        anchors.bottom: parent.bottom
                                        height: root.hairlineWidth
                                        visible: root.taskRowSelected(row) && !root.taskRowSelected(row + 1)
                                        color: root.activeTaskBorderColor
                                        opacity: Core.Theme.mode === "dark" ? 1.0 : 0.55
                                        z: 2
                                        Behavior on color { ColorAnimation { duration: Core.Theme.controlTransitionMs; easing.type: Easing.InOutCubic } }
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: root.hairlineWidth
                                        visible: root.taskRowSelected(row) && column === 0
                                        color: root.activeTaskBorderColor
                                        opacity: Core.Theme.mode === "dark" ? 1.0 : 0.55
                                        z: 2
                                        Behavior on color { ColorAnimation { duration: Core.Theme.controlTransitionMs; easing.type: Easing.InOutCubic } }
                                    }

                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: root.hairlineWidth
                                        visible: root.taskRowSelected(row) && column === root.columnTitles.length - 1
                                        color: root.activeTaskBorderColor
                                        opacity: Core.Theme.mode === "dark" ? 1.0 : 0.55
                                        z: 2
                                        Behavior on color { ColorAnimation { duration: Core.Theme.controlTransitionMs; easing.type: Easing.InOutCubic } }
                                    }

                                    Text {
                                        anchors.fill: parent
                                        anchors.leftMargin: Core.Theme.dp(8)
                                        anchors.rightMargin: Core.Theme.dp(8)
                                        verticalAlignment: Text.AlignVCenter
                                        text: root.taskCellText(column, name, taskType, status, progress, priority, duration, updatedAt)
                                        color: root.taskRowSelected(row) ? Core.Theme.color.navSelectedText : Core.Theme.color.text
                                        font.pixelSize: Core.Theme.fontSize.caption
                                        elide: Text.ElideRight
                                    }

                                    MouseArea {
                                        id: cellMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        preventStealing: true
                                        property real pressX: 0
                                        property real pressY: 0
                                        property real pressContentX: 0
                                        property bool selectionCommitted: false
                                        onPressed: function(mouse) {
                                            if (mouse.button === Qt.LeftButton) {
                                                const p = mapToItem(root, mouse.x, mouse.y)
                                                root.editingGroupRow = -1
                                                pressX = p.x
                                                pressY = p.y
                                                pressContentX = taskTable.contentX
                                                selectionCommitted = false
                                                root.taskHorizontalDragActive = false
                                                mouse.accepted = true
                                                return
                                            }
                                            if (mouse.button === Qt.RightButton) {
                                                const p = mapToItem(root, mouse.x, mouse.y)
                                                root.openTaskMenu(p.x, p.y, row)
                                                mouse.accepted = true
                                            }
                                        }
                                        onPositionChanged: function(mouse) {
                                            if (!pressed || mouse.buttons !== Qt.LeftButton)
                                                return
                                            const p = mapToItem(root, mouse.x, mouse.y)
                                            const dx = p.x - pressX
                                            const dy = p.y - pressY
                                            const threshold = Core.Theme.dp(6)
                                            if (!root.taskHorizontalDragActive && !selectionCommitted) {
                                                if (Math.abs(dx) < threshold && Math.abs(dy) < threshold)
                                                    return
                                                if (Math.abs(dx) > Math.abs(dy) * 1.35)
                                                    root.taskHorizontalDragActive = true
                                                else
                                                    commitSelection(mouse)
                                            }
                                            if (root.taskHorizontalDragActive) {
                                                const maxX = Math.max(0, taskTable.contentWidth - taskTable.width)
                                                taskTable.contentX = Math.max(0, Math.min(maxX, pressContentX - dx))
                                                mouse.accepted = true
                                            }
                                        }
                                        onReleased: function(mouse) {
                                            if (mouse.button === Qt.LeftButton && !root.taskHorizontalDragActive && !selectionCommitted)
                                                commitSelection(mouse)
                                            root.taskHorizontalDragActive = false
                                            mouse.accepted = true
                                        }
                                        onCanceled: root.taskHorizontalDragActive = false

                                        function commitSelection(mouse) {
                                            if (selectionCommitted)
                                                return
                                            selectionCommitted = true
                                            if (mouse.modifiers & Qt.ShiftModifier)
                                                root.selectTaskRange(row)
                                            else if (mouse.modifiers & Qt.ControlModifier)
                                                root.toggleTaskRow(row)
                                            else
                                                root.selectSingleTaskRow(row)
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            z: 0
                            onPressed: function(mouse) {
                                if (mouse.button === Qt.LeftButton) {
                                    root.editingGroupRow = -1
                                    mouse.accepted = false
                                    return
                                }
                                const p = mapToItem(root, mouse.x, mouse.y)
                                root.openTaskMenu(p.x, p.y, -1)
                                mouse.accepted = true
                            }
                        }

                        Item {
                            id: emptyTaskState
                            anchors.fill: parent
                            visible: !root.hasGroups
                            enabled: visible
                            z: 5

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.RightButton
                                onPressed: function(mouse) {
                                    const p = mapToItem(root, mouse.x, mouse.y)
                                    root.openGroupMenu(p.x, p.y, -1)
                                    mouse.accepted = true
                                }
                            }

                            Column {
                                z: 1
                                anchors.centerIn: parent
                                width: Math.min(Core.Theme.dp(320), parent.width - Core.Theme.dp(40))
                                spacing: Core.Theme.dp(10)

                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "暂无分组"
                                    color: Core.Theme.color.text
                                    font.pixelSize: Core.Theme.fontSize.subtitle
                                    font.family: Core.Theme.headingFontFamily
                                    font.weight: Core.Theme.headingFontWeight
                                }

                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "先新建分组，或直接导入 CSV/JSON 自动生成分组。"
                                    color: Core.Theme.color.mutedText
                                    font.pixelSize: Core.Theme.fontSize.caption
                                    wrapMode: Text.WordWrap
                                }

                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: Core.Theme.dp(8)
                                    AppButton {
                                        text: "新建分组"
                                        variant: "primary"
                                        onClicked: {
                                            if (root.appReady && App.taskStore)
                                                App.taskStore.addGroup()
                                        }
                                    }
                                    AppButton {
                                        text: "导入"
                                        variant: "soft"
                                        onClicked: importDialog.open()
                                    }
                                }
                            }
                        }
                    }
                }
            }

        }
    }

    MouseArea {
        anchors.fill: parent
        visible: root.editingGroupRow >= 0
        enabled: visible
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        z: 99999
        propagateComposedEvents: true
        onPressed: function(mouse) {
            if (root.editingGroupRow >= 0 && groupList) {
                const row = root.editingGroupRow
                const item = groupList.itemAtIndex(row)
                if (item) {
                    const p = mapToItem(item, mouse.x, mouse.y)
                    if (p.x >= 0 && p.x <= item.width && p.y >= 0 && p.y <= item.height) {
                        mouse.accepted = false
                        return
                    }
                }
            }
            root.finishGroupRename(true)
            mouse.accepted = false
        }
    }
}
