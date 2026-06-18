#include "task_store.h"

#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJSValue>
#include <QSet>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QSqlRecord>
#include <QVariantList>

namespace {

QString normalizedPath(QString path)
{
    if (path.startsWith(QStringLiteral("file:///")))
        path = path.mid(8);
    return QDir::toNativeSeparators(path);
}

QVariantMap variantToMap(const QVariant &value)
{
    if (value.canConvert<QVariantMap>())
        return value.toMap();
    if (value.canConvert<QJSValue>()) {
        const QJSValue js = value.value<QJSValue>();
        const QVariant converted = js.toVariant();
        if (converted.canConvert<QVariantMap>())
            return converted.toMap();
    }
    return {};
}

QString compactJsonObject(const QVariant &value)
{
    return QString::fromUtf8(QJsonDocument(QJsonObject::fromVariantMap(variantToMap(value))).toJson(QJsonDocument::Compact));
}

QSqlDatabase openConnection(const QString &connectionName, const QString &dbPath)
{
    if (QSqlDatabase::contains(connectionName)) {
        QSqlDatabase db = QSqlDatabase::database(connectionName);
        if (!db.isOpen())
            db.open();
        return db;
    }
    QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
    db.setDatabaseName(dbPath);
    if (!db.open()) {
        qWarning() << "TaskStore database open failed" << dbPath << db.lastError().text();
        return db;
    }
    QSqlQuery pragma(db);
    pragma.exec(QStringLiteral("PRAGMA journal_mode=WAL"));
    pragma.exec(QStringLiteral("PRAGMA synchronous=NORMAL"));
    pragma.exec(QStringLiteral("PRAGMA temp_store=MEMORY"));
    pragma.exec(QStringLiteral("PRAGMA foreign_keys=ON"));
    return db;
}

bool execSql(QSqlDatabase &db, const QString &sql)
{
    QSqlQuery query(db);
    return query.exec(sql);
}

QString firstMappedValue(const QVariantMap &row, const QStringList &keys, const QString &fallback = QString())
{
    for (const QString &key : keys) {
        const QVariant value = row.value(key);
        const QString text = value.toString().trimmed();
        if (!text.isEmpty())
            return text;
    }
    return fallback;
}

int boundedProgress(const QVariant &value)
{
    bool ok = false;
    const int number = int(value.toDouble(&ok));
    return ok ? qBound(0, number, 100) : 0;
}

QVariantMap taskFromImportRow(const QVariantMap &row, int index)
{
    const QString fallbackName = QStringLiteral("任务 %1").arg(index);
    QVariantMap task;
    task.insert(QStringLiteral("taskType"), firstMappedValue(row, {
        QStringLiteral("type"), QStringLiteral("task_type"), QStringLiteral("category"), QStringLiteral("类型"), QStringLiteral("分类")
    }, QStringLiteral("default")));
    task.insert(QStringLiteral("name"), firstMappedValue(row, {
        QStringLiteral("name"), QStringLiteral("title"), QStringLiteral("task"), QStringLiteral("任务"), QStringLiteral("名称"), QStringLiteral("标题")
    }, fallbackName));
    task.insert(QStringLiteral("status"), firstMappedValue(row, {
        QStringLiteral("status"), QStringLiteral("state"), QStringLiteral("url"), QStringLiteral("link"), QStringLiteral("链接"), QStringLiteral("状态")
    }, QStringLiteral("待处理")));
    task.insert(QStringLiteral("priority"), firstMappedValue(row, {
        QStringLiteral("priority"), QStringLiteral("level"), QStringLiteral("优先级")
    }, QStringLiteral("普通")));
    task.insert(QStringLiteral("duration"), firstMappedValue(row, {
        QStringLiteral("duration"), QStringLiteral("elapsed"), QStringLiteral("耗时")
    }, QStringLiteral("-")));
    task.insert(QStringLiteral("progress"), boundedProgress(row.value(QStringLiteral("progress"), row.value(QStringLiteral("进度")))));
    QVariantMap params;
    if (row.contains(QStringLiteral("params")) && row.value(QStringLiteral("params")).canConvert<QVariantMap>())
        params = row.value(QStringLiteral("params")).toMap();
    task.insert(QStringLiteral("params"), params);
    return task;
}

QVector<QVariantMap> parseCsvRows(const QString &text)
{
    QVector<QVariantMap> rows;
    const QStringList lines = text.split(QRegularExpression(QStringLiteral("\\r?\\n")), Qt::SkipEmptyParts);
    if (lines.isEmpty())
        return rows;
    const QChar delimiter = lines.first().count(u'\t') > lines.first().count(u',') ? QChar(u'\t') : QChar(u',');
    const QStringList headers = lines.first().split(delimiter);
    for (int i = 1; i < lines.size(); ++i) {
        const QStringList values = lines.at(i).split(delimiter);
        QVariantMap row;
        for (int c = 0; c < headers.size(); ++c)
            row.insert(headers.at(c).trimmed(), c < values.size() ? values.at(c).trimmed() : QString());
        rows.append(row);
    }
    return rows;
}

} // namespace

TaskGroupModel::TaskGroupModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int TaskGroupModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_groups.size();
}

QVariant TaskGroupModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_groups.size())
        return {};
    const TaskGroup &group = m_groups.at(index.row());
    switch (role) {
    case Qt::DisplayRole:
    case NameRole:
        return group.name;
    case CountRole:
        return group.count;
    case GroupIdRole:
        return group.id;
    default:
        return {};
    }
}

QHash<int, QByteArray> TaskGroupModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {CountRole, "count"},
        {GroupIdRole, "groupId"},
    };
}

int TaskGroupModel::groupIdAt(int row) const
{
    if (row < 0 || row >= m_groups.size())
        return 0;
    return m_groups.at(row).id;
}

int TaskGroupModel::rowForGroupId(int groupId) const
{
    for (int i = 0; i < m_groups.size(); ++i) {
        if (m_groups.at(i).id == groupId)
            return i;
    }
    return -1;
}

QVector<int> TaskGroupModel::groupIdsAt(const QVariant &rows) const
{
    QVector<int> ids;
    const QVariantList list = rows.toList();
    for (const QVariant &value : list) {
        const int id = groupIdAt(value.toInt());
        if (id > 0)
            ids.append(id);
    }
    return ids;
}

void TaskGroupModel::setRows(QVector<TaskGroup> groups)
{
    beginResetModel();
    m_groups = std::move(groups);
    endResetModel();
}

TaskTableModel::TaskTableModel(QObject *parent)
    : QAbstractTableModel(parent)
{
}

int TaskTableModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rowCount;
}

int TaskTableModel::columnCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : 7;
}

QVariant TaskTableModel::data(const QModelIndex &index, int role) const
{
    const TaskRow *task = rowAt(index.row());
    if (!task)
        return {};
    if (role == Qt::DisplayRole) {
        switch (index.column()) {
        case 0: return task->name;
        case 1: return task->type;
        case 2: return task->status;
        case 3: return task->progress;
        case 4: return task->priority;
        case 5: return task->duration;
        case 6: return task->updatedAt;
        default: return {};
        }
    }
    switch (role) {
    case NameRole: return task->name;
    case StatusRole: return task->status;
    case TypeRole: return task->type;
    case ProgressRole: return task->progress;
    case PriorityRole: return task->priority;
    case DurationRole: return task->duration;
    case UpdatedAtRole: return task->updatedAt;
    case TaskIdRole: return task->id;
    default: return {};
    }
}

QHash<int, QByteArray> TaskTableModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {StatusRole, "status"},
        {TypeRole, "taskType"},
        {ProgressRole, "progress"},
        {PriorityRole, "priority"},
        {DurationRole, "duration"},
        {UpdatedAtRole, "updatedAt"},
        {TaskIdRole, "taskId"},
    };
}

void TaskTableModel::configure(const QString &dbPath, bool lowMemory)
{
    m_dbPath = dbPath;
    m_lowMemory = lowMemory;
}

void TaskTableModel::setLowMemory(bool enabled)
{
    if (m_lowMemory == enabled)
        return;
    m_lowMemory = enabled;
    clearCache();
}

void TaskTableModel::setGroup(int groupId)
{
    QSqlDatabase db = openConnection(QStringLiteral("cpp_tasks_table_count_%1").arg(reinterpret_cast<quintptr>(this)), m_dbPath);
    int count = 0;
    if (db.isOpen() && groupId > 0) {
        QSqlQuery query(db);
        query.prepare(QStringLiteral("SELECT COUNT(*) FROM tasks WHERE group_id = ?"));
        query.addBindValue(groupId);
        if (query.exec() && query.next())
            count = query.value(0).toInt();
    }

    beginResetModel();
    m_groupId = groupId;
    m_rowCount = count;
    clearCache();
    endResetModel();
    prefetchAround(0);
}

void TaskTableModel::clearCache()
{
    m_pages.clear();
    m_lruPages.clear();
    m_lastRowValid = false;
}

void TaskTableModel::prefetchAround(int row)
{
    if (m_groupId <= 0 || m_rowCount <= 0)
        return;
    const int page = qMax(0, row / cacheProfile().pageSize);
    rowAt(page * cacheProfile().pageSize);
    if (!m_lowMemory)
        rowAt((page + 1) * cacheProfile().pageSize);
}

int TaskTableModel::taskIdAt(int row) const
{
    const TaskRow *task = rowAt(row);
    return task ? task->id : 0;
}

QString TaskTableModel::taskTypeAt(int row) const
{
    const TaskRow *task = rowAt(row);
    return task ? task->type : QStringLiteral("default");
}

QVariantMap TaskTableModel::taskDetails(int taskId) const
{
    if (taskId <= 0)
        return {};
    QSqlDatabase db = openConnection(QStringLiteral("cpp_tasks_details_%1").arg(reinterpret_cast<quintptr>(this)), m_dbPath);
    QSqlQuery query(db);
    query.prepare(QStringLiteral(
        "SELECT id, group_id, task_type, name, status, progress, priority, duration, updated_at, params_json "
        "FROM tasks WHERE id = ?"));
    query.addBindValue(taskId);
    if (!query.exec() || !query.next())
        return {};
    return {
        {QStringLiteral("id"), query.value(0).toInt()},
        {QStringLiteral("groupId"), query.value(1).toInt()},
        {QStringLiteral("taskType"), query.value(2).toString()},
        {QStringLiteral("name"), query.value(3).toString()},
        {QStringLiteral("status"), query.value(4).toString()},
        {QStringLiteral("progress"), query.value(5).toInt()},
        {QStringLiteral("priority"), query.value(6).toString()},
        {QStringLiteral("duration"), query.value(7).toString()},
        {QStringLiteral("updatedAt"), query.value(8).toString()},
        {QStringLiteral("params"), paramsFromJson(query.value(9).toString())},
    };
}

TaskTableModel::CacheProfile TaskTableModel::cacheProfile() const
{
    return m_lowMemory ? CacheProfile{96, 2} : CacheProfile{256, 6};
}

QVector<TaskRow> TaskTableModel::loadPage(int pageIndex) const
{
    QVector<TaskRow> rows;
    if (m_groupId <= 0)
        return rows;
    QSqlDatabase db = openConnection(QStringLiteral("cpp_tasks_table_%1").arg(reinterpret_cast<quintptr>(this)), m_dbPath);
    QSqlQuery query(db);
    query.prepare(QStringLiteral(
        "SELECT id, group_id, task_type, name, status, progress, priority, duration, updated_at, params_json "
        "FROM tasks WHERE group_id = ? ORDER BY id LIMIT ? OFFSET ?"));
    query.addBindValue(m_groupId);
    query.addBindValue(cacheProfile().pageSize);
    query.addBindValue(pageIndex * cacheProfile().pageSize);
    if (!query.exec())
        return rows;
    while (query.next()) {
        TaskRow row;
        row.id = query.value(0).toInt();
        row.groupId = query.value(1).toInt();
        row.type = query.value(2).toString();
        row.name = query.value(3).toString();
        row.status = query.value(4).toString();
        row.progress = query.value(5).toInt();
        row.priority = query.value(6).toString();
        row.duration = query.value(7).toString();
        row.updatedAt = query.value(8).toString();
        row.params = paramsFromJson(query.value(9).toString());
        rows.append(row);
    }
    return rows;
}

const TaskRow *TaskTableModel::rowAt(int row) const
{
    if (row < 0 || row >= m_rowCount)
        return nullptr;
    const int pageIndex = row / cacheProfile().pageSize;
    const int offset = row % cacheProfile().pageSize;
    if (!m_pages.contains(pageIndex))
        rememberPage(pageIndex, loadPage(pageIndex));
    const QVector<TaskRow> page = m_pages.value(pageIndex);
    if (offset < 0 || offset >= page.size())
        return nullptr;
    m_lastRow = page.at(offset);
    m_lastRowValid = true;
    return &m_lastRow;
}

void TaskTableModel::rememberPage(int pageIndex, QVector<TaskRow> rows) const
{
    m_pages.insert(pageIndex, std::move(rows));
    m_lruPages.removeAll(pageIndex);
    m_lruPages.append(pageIndex);
    while (m_lruPages.size() > cacheProfile().maxPages) {
        const int evict = m_lruPages.takeFirst();
        m_pages.remove(evict);
    }
}

QVariantMap TaskTableModel::paramsFromJson(const QString &text)
{
    const QJsonDocument doc = QJsonDocument::fromJson(text.toUtf8());
    return doc.isObject() ? doc.object().toVariantMap() : QVariantMap{};
}

TaskStore::TaskStore(const QString &rootPath, QObject *performance, QObject *parent)
    : QObject(parent)
    , m_rootPath(rootPath)
    , m_performance(performance)
{
    const QString base = m_rootPath.isEmpty() ? QDir::currentPath() : m_rootPath;
    m_dbPath = QDir(base).absoluteFilePath(QStringLiteral("user_data/data/tasks.db"));
    initializeDatabase();
    const bool lowMemory = m_performance ? m_performance->property("lowMemoryMode").toBool() : false;
    m_taskModel.configure(m_dbPath, lowMemory);
    if (m_performance) {
        connect(m_performance, SIGNAL(lowMemoryModeChanged(bool)), &m_taskModel, SLOT(setLowMemory(bool)));
    }
    loadGroups();
    selectGroup(0);
}

TaskStore::~TaskStore()
{
    const QStringList names = QSqlDatabase::connectionNames();
    for (const QString &name : names) {
        if (name.startsWith(QStringLiteral("cpp_tasks_"))) {
            QSqlDatabase::removeDatabase(name);
        }
    }
}

void TaskStore::initializeDatabase()
{
    QFileInfo info(m_dbPath);
    QDir().mkpath(info.absolutePath());
    QSqlDatabase db = openConnection(connectionName(), m_dbPath);
    if (!db.isOpen())
        return;
    execSql(db, QStringLiteral(
        "CREATE TABLE IF NOT EXISTS task_groups ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "name TEXT NOT NULL UNIQUE,"
        "sort_order INTEGER NOT NULL DEFAULT 0,"
        "created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)"));
    execSql(db, QStringLiteral(
        "CREATE TABLE IF NOT EXISTS tasks ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "group_id INTEGER NOT NULL REFERENCES task_groups(id) ON DELETE CASCADE,"
        "task_type TEXT NOT NULL DEFAULT 'default',"
        "name TEXT NOT NULL,"
        "status TEXT NOT NULL DEFAULT '待处理',"
        "progress INTEGER NOT NULL DEFAULT 0,"
        "priority TEXT NOT NULL DEFAULT '普通',"
        "duration TEXT NOT NULL DEFAULT '-',"
        "params_json TEXT NOT NULL DEFAULT '{}',"
        "updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)"));
    execSql(db, QStringLiteral("CREATE INDEX IF NOT EXISTS idx_tasks_group_id_id ON tasks(group_id, id)"));
}

void TaskStore::loadGroups()
{
    const int oldGroupCount = m_groupCount;
    QVector<TaskGroup> groups;
    QSqlDatabase db = openConnection(connectionName(), m_dbPath);
    QSqlQuery query(db);
    query.exec(QStringLiteral(
        "SELECT g.id, g.name, COUNT(t.id) "
        "FROM task_groups g LEFT JOIN tasks t ON t.group_id = g.id "
        "GROUP BY g.id, g.name, g.sort_order ORDER BY g.sort_order, g.id"));
    while (query.next()) {
        groups.append({query.value(0).toInt(), query.value(1).toString(), query.value(2).toInt()});
    }
    m_groups = groups;
    m_groupCount = m_groups.size();
    m_groupModel.setRows(std::move(groups));
    if (m_groupCount != oldGroupCount)
        emit groupCountChanged();
}

void TaskStore::selectGroup(int index)
{
    if (m_groups.isEmpty()) {
        m_currentGroupIndex = -1;
        m_taskModel.setGroup(0);
        emit groupChanged();
        return;
    }
    m_currentGroupIndex = qBound(0, index, m_groups.size() - 1);
    m_taskModel.setGroup(currentGroupId());
    emit groupChanged();
}

void TaskStore::prefetchAround(int row)
{
    m_taskModel.prefetchAround(row);
}

int TaskStore::taskIdAt(int row) const
{
    return m_taskModel.taskIdAt(row);
}

QString TaskStore::taskTypeAt(int row) const
{
    return m_taskModel.taskTypeAt(row);
}

QVariantMap TaskStore::taskDetails(int taskId) const
{
    return m_taskModel.taskDetails(taskId);
}

void TaskStore::saveTaskDetails(int taskId, const QVariant &values)
{
    const QVariantMap data = valuesToMap(values);
    if (taskId <= 0)
        return;
    QSqlDatabase db = openConnection(connectionName(), m_dbPath);
    QSqlQuery query(db);
    query.prepare(QStringLiteral(
        "UPDATE tasks SET task_type=?, name=?, status=?, progress=?, priority=?, duration=?, params_json=?, updated_at=CURRENT_TIMESTAMP WHERE id=?"));
    query.addBindValue(data.value(QStringLiteral("taskType"), QStringLiteral("default")).toString());
    query.addBindValue(data.value(QStringLiteral("name"), QStringLiteral("未命名任务")).toString());
    query.addBindValue(data.value(QStringLiteral("status"), QStringLiteral("待处理")).toString());
    query.addBindValue(qBound(0, data.value(QStringLiteral("progress"), 0).toInt(), 100));
    query.addBindValue(data.value(QStringLiteral("priority"), QStringLiteral("普通")).toString());
    query.addBindValue(data.value(QStringLiteral("duration"), QStringLiteral("-")).toString());
    query.addBindValue(compactJsonObject(data.value(QStringLiteral("params"))));
    query.addBindValue(taskId);
    query.exec();
    refresh();
    setStatusMessage(QStringLiteral("未命名任务"));
}

void TaskStore::createTask(const QVariant &values)
{
    const int groupId = currentGroupId();
    if (groupId <= 0) {
        setStatusMessage(QStringLiteral("请先新建分组"));
        return;
    }
    const QVariantMap data = valuesToMap(values);
    const int count = qBound(1, data.value(QStringLiteral("count"), 1).toInt(), 10000);
    QSqlDatabase db = openConnection(connectionName(), m_dbPath);
    db.transaction();
    QSqlQuery query(db);
    query.prepare(QStringLiteral(
        "INSERT INTO tasks(group_id, task_type, name, status, progress, priority, duration, params_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"));
    const QString baseName = data.value(QStringLiteral("name"), QStringLiteral("新建任务")).toString();
    for (int i = 0; i < count; ++i) {
        query.bindValue(0, groupId);
        query.bindValue(1, data.value(QStringLiteral("taskType"), QStringLiteral("default")).toString());
        query.bindValue(2, count > 1 ? QStringLiteral("%1 %2").arg(baseName).arg(i + 1) : baseName);
        query.bindValue(3, data.value(QStringLiteral("status"), statusUrlFor(i + 1)).toString());
        query.bindValue(4, qBound(0, data.value(QStringLiteral("progress"), 0).toInt(), 100));
        query.bindValue(5, data.value(QStringLiteral("priority"), QStringLiteral("普通")).toString());
        query.bindValue(6, data.value(QStringLiteral("duration"), QStringLiteral("-")).toString());
        query.bindValue(7, compactJsonObject(data.value(QStringLiteral("params"))));
        query.exec();
    }
    db.commit();
    refresh();
    setStatusMessage(count > 1 ? QStringLiteral("已创建 %1 条任务").arg(count) : QStringLiteral("未命名任务"));
}

QVariantMap TaskStore::parseClipboardTask(const QString &text) const
{
    const QString raw = text.trimmed();
    const QString type = taskTypeFromText(raw);
    QVariantMap params;
    params.insert(type == QLatin1String("script") ? QStringLiteral("script") : QStringLiteral("source"), raw);
    return {
        {QStringLiteral("taskType"), type},
        {QStringLiteral("name"), raw.left(120)},
        {QStringLiteral("status"), raw},
        {QStringLiteral("progress"), 0},
        {QStringLiteral("priority"), QStringLiteral("普通")},
        {QStringLiteral("duration"), QStringLiteral("-")},
        {QStringLiteral("params"), params},
    };
}

void TaskStore::addGroup()
{
    const QString baseName = QString::fromUtf8("\xE6\x96\xB0\xE5\xBB\xBA\xE5\x88\x86\xE7\xBB\x84");
    const QString failedMessage = QString::fromUtf8("\xE6\x96\xB0\xE5\xBB\xBA\xE5\x88\x86\xE7\xBB\x84\xE5\xA4\xB1\xE8\xB4\xA5");
    const QString createdMessage = QString::fromUtf8("\xE5\xB7\xB2\xE6\x96\xB0\xE5\xBB\xBA\xE5\x88\x86\xE7\xBB\x84");
    auto fail = [&](const QString &detail) {
        qWarning() << "TaskStore.addGroup failed" << detail << "db=" << m_dbPath;
        setStatusMessage(detail.isEmpty() ? failedMessage : QStringLiteral("%1: %2").arg(failedMessage, detail));
    };

    QSqlDatabase db = openConnection(connectionName(), m_dbPath);
    if (!db.isOpen()) {
        fail(db.lastError().text());
        return;
    }

    QSqlQuery orderQuery(db);
    if (!orderQuery.exec(QStringLiteral("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM task_groups")))
        qWarning() << "TaskStore.addGroup order query failed" << orderQuery.lastError().text();
    int order = 1;
    if (orderQuery.next())
        order = orderQuery.value(0).toInt();

    QString name = baseName;
    int suffix = 2;
    while (true) {
        QSqlQuery exists(db);
        exists.prepare(QStringLiteral("SELECT 1 FROM task_groups WHERE name=?"));
        exists.addBindValue(name);
        if (!exists.exec()) {
            qWarning() << "TaskStore.addGroup exists query failed" << exists.lastError().text();
            break;
        }
        if (!exists.next())
            break;
        name = QStringLiteral("%1 %2").arg(baseName).arg(suffix++);
    }

    QSqlQuery query(db);
    query.prepare(QStringLiteral("INSERT INTO task_groups(name, sort_order) VALUES (?, ?)"));
    query.addBindValue(name);
    query.addBindValue(order);
    if (!query.exec()) {
        const QString firstError = query.lastError().text();
        initializeDatabase();
        query.prepare(QStringLiteral("INSERT INTO task_groups(name, sort_order) VALUES (?, ?)"));
        query.addBindValue(name);
        query.addBindValue(order);
        if (!query.exec()) {
            const QString secondError = query.lastError().text();
            fail(secondError.isEmpty() ? firstError : secondError);
            return;
        }
    }
    loadGroups();
    selectGroup(m_groups.size() - 1);
    setStatusMessage(createdMessage);
}

void TaskStore::deleteGroupRows(const QVariant &rows)
{
    const QVector<int> ids = m_groupModel.groupIdsAt(rows);
    if (ids.isEmpty())
        return;
    QSqlDatabase db = openConnection(connectionName(), m_dbPath);
    db.transaction();
    QSqlQuery query(db);
    query.prepare(QStringLiteral("DELETE FROM task_groups WHERE id=?"));
    for (int id : ids) {
        query.bindValue(0, id);
        query.exec();
    }
    db.commit();
    loadGroups();
    selectGroup(qMin(m_currentGroupIndex, qMax(0, m_groups.size() - 1)));
}

void TaskStore::renameGroupAt(int index, const QString &name)
{
    const int id = groupIdAt(index);
    if (id <= 0 || name.trimmed().isEmpty())
        return;
    QSqlDatabase db = openConnection(connectionName(), m_dbPath);
    QSqlQuery query(db);
    query.prepare(QStringLiteral("UPDATE task_groups SET name=? WHERE id=?"));
    query.addBindValue(name.trimmed());
    query.addBindValue(id);
    query.exec();
    loadGroups();
}

void TaskStore::moveGroup(int sourceIndex, int targetIndex)
{
    if (sourceIndex < 0 || sourceIndex >= m_groups.size() || targetIndex < 0 || targetIndex >= m_groups.size())
        return;
    const TaskGroup group = m_groups.takeAt(sourceIndex);
    m_groups.insert(targetIndex, group);
    QSqlDatabase db = openConnection(connectionName(), m_dbPath);
    db.transaction();
    QSqlQuery query(db);
    query.prepare(QStringLiteral("UPDATE task_groups SET sort_order=? WHERE id=?"));
    for (int i = 0; i < m_groups.size(); ++i) {
        query.bindValue(0, i);
        query.bindValue(1, m_groups.at(i).id);
        query.exec();
    }
    db.commit();
    loadGroups();
    selectGroup(targetIndex);
}

void TaskStore::deleteTaskRows(const QVariant &rows)
{
    const QVariantList list = rows.toList();
    QVector<int> ids;
    for (const QVariant &value : list) {
        const int id = taskIdAt(value.toInt());
        if (id > 0)
            ids.append(id);
    }
    if (ids.isEmpty())
        return;
    QSqlDatabase db = openConnection(connectionName(), m_dbPath);
    db.transaction();
    QSqlQuery query(db);
    query.prepare(QStringLiteral("DELETE FROM tasks WHERE id=?"));
    for (int id : ids) {
        query.bindValue(0, id);
        query.exec();
    }
    db.commit();
    refresh();
}

void TaskStore::importFile(const QString &path)
{
    const QString filePath = normalizedPath(path);
    QFile file(filePath);
    if (!file.exists() || !file.open(QIODevice::ReadOnly)) {
        setStatusMessage(QStringLiteral("导入失败：文件不存在或无法读取"));
        return;
    }

    const QFileInfo info(filePath);
    QString groupName = info.completeBaseName().isEmpty() ? QStringLiteral("导入任务") : info.completeBaseName();
    QVector<QVariantMap> importedRows;
    const QByteArray payload = file.readAll();
    if (info.suffix().compare(QStringLiteral("json"), Qt::CaseInsensitive) == 0) {
        const QJsonDocument doc = QJsonDocument::fromJson(payload);
        QVariant data = doc.toVariant();
        if (data.canConvert<QVariantMap>()) {
            const QVariantMap root = data.toMap();
            groupName = root.value(QStringLiteral("group"), root.value(QStringLiteral("name"), groupName)).toString();
            data = root.value(QStringLiteral("tasks"), root.value(QStringLiteral("items"), root.value(QStringLiteral("rows"))));
        }
        const QVariantList list = data.toList();
        for (int i = 0; i < list.size(); ++i) {
            if (list.at(i).canConvert<QVariantMap>())
                importedRows.append(taskFromImportRow(list.at(i).toMap(), i + 1));
            else
                importedRows.append(taskFromImportRow({{QStringLiteral("name"), list.at(i)}}, i + 1));
        }
    } else {
        const QString text = QString::fromUtf8(payload);
        const QVector<QVariantMap> rows = parseCsvRows(text);
        for (int i = 0; i < rows.size(); ++i)
            importedRows.append(taskFromImportRow(rows.at(i), i + 1));
    }

    if (importedRows.isEmpty()) {
        setStatusMessage(QStringLiteral("导入失败：没有可导入的任务"));
        return;
    }

    QSqlDatabase db = openConnection(connectionName(), m_dbPath);
    db.transaction();
    QSqlQuery orderQuery(db);
    orderQuery.exec(QStringLiteral("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM task_groups"));
    int order = 1;
    if (orderQuery.next())
        order = orderQuery.value(0).toInt();

    QSqlQuery groupQuery(db);
    groupQuery.prepare(QStringLiteral("INSERT INTO task_groups(name, sort_order) VALUES (?, ?)"));
    groupQuery.addBindValue(groupName);
    groupQuery.addBindValue(order);
    if (!groupQuery.exec()) {
        db.rollback();
        setStatusMessage(QStringLiteral("导入失败：无法创建分组"));
        return;
    }
    const int groupId = groupQuery.lastInsertId().toInt();

    QSqlQuery insert(db);
    insert.prepare(QStringLiteral(
        "INSERT INTO tasks(group_id, task_type, name, status, progress, priority, duration, params_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"));
    for (const QVariantMap &task : importedRows) {
        insert.bindValue(0, groupId);
        insert.bindValue(1, task.value(QStringLiteral("taskType"), QStringLiteral("default")).toString());
        insert.bindValue(2, task.value(QStringLiteral("name"), QStringLiteral("未命名任务")).toString());
        insert.bindValue(3, task.value(QStringLiteral("status"), QStringLiteral("待处理")).toString());
        insert.bindValue(4, qBound(0, task.value(QStringLiteral("progress"), 0).toInt(), 100));
        insert.bindValue(5, task.value(QStringLiteral("priority"), QStringLiteral("普通")).toString());
        insert.bindValue(6, task.value(QStringLiteral("duration"), QStringLiteral("-")).toString());
        insert.bindValue(7, compactJsonObject(task.value(QStringLiteral("params"))));
        if (!insert.exec()) {
            db.rollback();
            setStatusMessage(QStringLiteral("导入失败：写入任务失败"));
            return;
        }
    }
    db.commit();
    loadGroups();
    selectGroup(m_groupModel.rowForGroupId(groupId));
    setStatusMessage(QStringLiteral("已导入 %1 条任务").arg(importedRows.size()));
}

void TaskStore::refresh()
{
    const int groupId = currentGroupId();
    loadGroups();
    const int restored = m_groupModel.rowForGroupId(groupId);
    selectGroup(restored >= 0 ? restored : qMin(m_currentGroupIndex, qMax(0, m_groups.size() - 1)));
}

void TaskStore::clearCaches()
{
    m_taskModel.clearCache();
}

int TaskStore::currentGroupId() const
{
    return groupIdAt(m_currentGroupIndex);
}

int TaskStore::groupIdAt(int index) const
{
    if (index < 0 || index >= m_groups.size())
        return 0;
    return m_groups.at(index).id;
}

QVariantMap TaskStore::valuesToMap(const QVariant &values) const
{
    return variantToMap(values);
}

void TaskStore::setStatusMessage(const QString &message)
{
    if (m_statusMessage == message)
        return;
    m_statusMessage = message;
    emit statusMessageChanged();
}

void TaskStore::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

QString TaskStore::connectionName() const
{
    return QStringLiteral("cpp_tasks_store_%1").arg(reinterpret_cast<quintptr>(this));
}

QString TaskStore::taskTypeFromText(const QString &text)
{
    const QString lower = text.trimmed().toLower();
    if (lower.startsWith(QStringLiteral("http://")) || lower.startsWith(QStringLiteral("https://")) || lower.startsWith(QStringLiteral("url:")))
        return QStringLiteral("download");
    if (lower.startsWith(QStringLiteral("script:")) || lower.startsWith(QStringLiteral("cmd:")) || lower.startsWith(QStringLiteral("python:")))
        return QStringLiteral("script");
    return QStringLiteral("default");
}

QString TaskStore::statusUrlFor(int id)
{
    return QStringLiteral("https://example.local/tasks/%1/source/%2?token=%3")
        .arg(id)
        .arg(100000 + id)
        .arg(900000000 + id);
}
