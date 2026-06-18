#pragma once

#include <QAbstractListModel>
#include <QAbstractTableModel>
#include <QHash>
#include <QObject>
#include <QVariantMap>
#include <QVector>

struct TaskGroup {
    int id = 0;
    QString name;
    int count = 0;
};

struct TaskRow {
    int id = 0;
    int groupId = 0;
    QString type;
    QString name;
    QString status;
    int progress = 0;
    QString priority;
    QString duration;
    QString updatedAt;
    QVariantMap params;
};

class TaskGroupModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        CountRole,
        GroupIdRole
    };

    explicit TaskGroupModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int groupIdAt(int row) const;
    int rowForGroupId(int groupId) const;
    QVector<int> groupIdsAt(const QVariant &rows) const;
    void setRows(QVector<TaskGroup> groups);

private:
    QVector<TaskGroup> m_groups;
};

class TaskTableModel : public QAbstractTableModel {
    Q_OBJECT
public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        StatusRole,
        TypeRole,
        ProgressRole,
        PriorityRole,
        DurationRole,
        UpdatedAtRole,
        TaskIdRole
    };

    explicit TaskTableModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    int columnCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void configure(const QString &dbPath, bool lowMemory);
    void setGroup(int groupId);
    void clearCache();
    void prefetchAround(int row);
    int taskIdAt(int row) const;
    QString taskTypeAt(int row) const;
    QVariantMap taskDetails(int taskId) const;

public slots:
    void setLowMemory(bool enabled);

private:
    struct CacheProfile {
        int pageSize = 256;
        int maxPages = 6;
    };

    CacheProfile cacheProfile() const;
    QVector<TaskRow> loadPage(int pageIndex) const;
    const TaskRow *rowAt(int row) const;
    void rememberPage(int pageIndex, QVector<TaskRow> rows) const;
    static QVariantMap paramsFromJson(const QString &text);

    QString m_dbPath;
    int m_groupId = 0;
    int m_rowCount = 0;
    bool m_lowMemory = false;
    mutable QHash<int, QVector<TaskRow>> m_pages;
    mutable QVector<int> m_lruPages;
    mutable TaskRow m_lastRow;
    mutable bool m_lastRowValid = false;
};

class TaskStore : public QObject {
    Q_OBJECT
    Q_PROPERTY(QObject *groupModel READ groupModel CONSTANT)
    Q_PROPERTY(QObject *taskModel READ taskModel CONSTANT)
    Q_PROPERTY(int currentGroupIndex READ currentGroupIndex NOTIFY groupChanged)
    Q_PROPERTY(int groupCount READ groupCount NOTIFY groupCountChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusMessageChanged)
public:
    explicit TaskStore(const QString &rootPath = QString(), QObject *performance = nullptr, QObject *parent = nullptr);
    ~TaskStore() override;

    QObject *groupModel() { return &m_groupModel; }
    QObject *taskModel() { return &m_taskModel; }
    int currentGroupIndex() const { return m_currentGroupIndex; }
    int groupCount() const { return m_groupCount; }
    bool busy() const { return m_busy; }
    QString statusMessage() const { return m_statusMessage; }

    Q_INVOKABLE void selectGroup(int index);
    Q_INVOKABLE void prefetchAround(int row);
    Q_INVOKABLE int taskIdAt(int row) const;
    Q_INVOKABLE QString taskTypeAt(int row) const;
    Q_INVOKABLE QVariantMap taskDetails(int taskId) const;
    Q_INVOKABLE void saveTaskDetails(int taskId, const QVariant &values);
    Q_INVOKABLE void createTask(const QVariant &values);
    Q_INVOKABLE QVariantMap parseClipboardTask(const QString &text) const;
    Q_INVOKABLE void addGroup();
    Q_INVOKABLE void deleteGroupRows(const QVariant &rows);
    Q_INVOKABLE void renameGroupAt(int index, const QString &name);
    Q_INVOKABLE void moveGroup(int sourceIndex, int targetIndex);
    Q_INVOKABLE void deleteTaskRows(const QVariant &rows);
    Q_INVOKABLE void importFile(const QString &path);
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void clearCaches();

signals:
    void groupChanged();
    void groupCountChanged();
    void busyChanged();
    void statusMessageChanged();

private:
    void initializeDatabase();
    void loadGroups();
    void reloadCurrentGroup();
    int currentGroupId() const;
    int groupIdAt(int index) const;
    QVariantMap valuesToMap(const QVariant &values) const;
    void setStatusMessage(const QString &message);
    void setBusy(bool busy);
    QString connectionName() const;
    static QString taskTypeFromText(const QString &text);
    static QString statusUrlFor(int id);

    QString m_rootPath;
    QString m_dbPath;
    QObject *m_performance = nullptr;
    TaskGroupModel m_groupModel;
    TaskTableModel m_taskModel;
    QVector<TaskGroup> m_groups;
    int m_groupCount = 0;
    int m_currentGroupIndex = 0;
    bool m_busy = false;
    QString m_statusMessage;
};
