#pragma once

#include <QtCore/QHash>
#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QSet>
#include <QtCore/QUrl>
#include <QtCore/QVariantMap>
#include <QtQml/QQmlComponent>
#include <QtQml/qqmlregistration.h>
#include <QtQuick/QQuickWindow>

class NativeChildWindowManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QObject *bridge READ bridge WRITE setBridge NOTIFY bridgeChanged)

public:
    explicit NativeChildWindowManager(QObject *parent = nullptr);
    ~NativeChildWindowManager() override;

    QObject *bridge() const;
    void setBridge(QObject *bridge);

    Q_INVOKABLE QObject *openChild(const QUrl &windowSource,
                                   const QUrl &pageSource,
                                   const QString &pageTitle,
                                   const QString &windowKey,
                                   QQuickWindow *parentWindow,
                                   const QVariantMap &properties = {});
    Q_INVOKABLE void closeChild(const QString &windowKey);
    Q_INVOKABLE void closeAll();

signals:
    void bridgeChanged();

private slots:
    void handleWindowEvent(const QString &eventType, const QVariant &payload);

private:
    QQmlComponent *componentFor(const QUrl &source);
    void connectWindow(QObject *window, const QString &windowKey);
    void forgetWindow(QObject *window);
    void requestWindowClose(QObject *window);
    void destroyReleasedWindow(QObject *window);

    QPointer<QObject> m_bridge;
    QHash<QUrl, QQmlComponent *> m_components;
    QHash<QString, QPointer<QObject>> m_windowsByKey;
    QHash<QObject *, QString> m_keysByWindow;
    QSet<QObject *> m_releasingWindows;
};
