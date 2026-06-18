#include "native_child_window_manager.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QDebug>
#include <QtCore/QEvent>
#include <QtCore/QMetaObject>
#include <QtCore/QTimer>
#include <QtCore/QVariant>
#include <QtQml/QQmlEngine>

NativeChildWindowManager::NativeChildWindowManager(QObject *parent)
    : QObject(parent) {
}

NativeChildWindowManager::~NativeChildWindowManager() {
    closeAll();
    qDeleteAll(m_components);
    m_components.clear();
}

QObject *NativeChildWindowManager::bridge() const {
    return m_bridge.data();
}

void NativeChildWindowManager::setBridge(QObject *bridge) {
    if (m_bridge == bridge)
        return;
    m_bridge = bridge;
    emit bridgeChanged();
}

QObject *NativeChildWindowManager::openChild(const QUrl &windowSource,
                                             const QUrl &pageSource,
                                             const QString &pageTitle,
                                             const QString &windowKey,
                                             QQuickWindow *parentWindow,
                                             const QVariantMap &properties) {
    if (!windowSource.isValid() || windowKey.isEmpty())
        return nullptr;

    if (auto existing = m_windowsByKey.value(windowKey)) {
        requestWindowClose(existing);
    }

    QQmlComponent *component = componentFor(windowSource);
    if (!component || component->isError()) {
        if (component)
            qWarning() << "NativeChildWindowManager component error" << windowSource << component->errors();
        else
            qWarning() << "NativeChildWindowManager missing component" << windowSource;
        return nullptr;
    }

    QVariantMap initialProperties = properties;
    initialProperties.insert(QStringLiteral("bridge"), QVariant::fromValue(m_bridge.data()));
    initialProperties.insert(QStringLiteral("pageSource"), pageSource);
    initialProperties.insert(QStringLiteral("pageTitle"), pageTitle);
    initialProperties.insert(QStringLiteral("windowKey"), windowKey);
    initialProperties.insert(QStringLiteral("pageProperties"), properties);
    if (properties.contains(QStringLiteral("taskId")))
        initialProperties.insert(QStringLiteral("taskId"), properties.value(QStringLiteral("taskId")));
    if (properties.contains(QStringLiteral("taskType")))
        initialProperties.insert(QStringLiteral("taskType"), properties.value(QStringLiteral("taskType")));
    initialProperties.insert(QStringLiteral("alwaysOnTop"), false);
    if (parentWindow)
        initialProperties.insert(QStringLiteral("parentWindow"), QVariant::fromValue(parentWindow));

    QObject *window = component->createWithInitialProperties(initialProperties);
    if (!window) {
        qWarning() << "NativeChildWindowManager create failed" << windowSource << component->errors();
        return nullptr;
    }

    QQmlEngine::setObjectOwnership(window, QQmlEngine::CppOwnership);
    window->setParent(this);
    connectWindow(window, windowKey);

    QMetaObject::invokeMethod(window, "applyParentWindow", Qt::DirectConnection);
    QMetaObject::invokeMethod(window, "restorePersistedWindowState", Qt::DirectConnection);
    QMetaObject::invokeMethod(window, "show", Qt::DirectConnection);
    return window;
}

void NativeChildWindowManager::closeChild(const QString &windowKey) {
    if (auto window = m_windowsByKey.value(windowKey))
        requestWindowClose(window);
}

void NativeChildWindowManager::closeAll() {
    const auto windows = m_windowsByKey;
    for (auto it = windows.cbegin(); it != windows.cend(); ++it) {
        if (it.value())
            requestWindowClose(it.value());
    }
}

QQmlComponent *NativeChildWindowManager::componentFor(const QUrl &source) {
    if (auto component = m_components.value(source))
        return component;
    QQmlEngine *engine = qmlEngine(this);
    if (!engine)
        return nullptr;
    auto *component = new QQmlComponent(engine, source, this);
    if (component->isError()) {
        qWarning() << "NativeChildWindowManager componentFor error" << source << component->errors();
        delete component;
        return nullptr;
    }
    m_components.insert(source, component);
    return component;
}

void NativeChildWindowManager::connectWindow(QObject *window, const QString &windowKey) {
    if (!window)
        return;
    m_windowsByKey.insert(windowKey, window);
    m_keysByWindow.insert(window, windowKey);
    connect(window, &QObject::destroyed, this, [this, window]() {
        m_releasingWindows.remove(window);
        forgetWindow(window);
    });
    connect(window, SIGNAL(windowEvent(QString,QVariant)), this, SLOT(handleWindowEvent(QString,QVariant)));
}

void NativeChildWindowManager::handleWindowEvent(const QString &eventType, const QVariant &payload) {
    Q_UNUSED(payload)
    if (eventType != QLatin1String("closing"))
        return;
    QObject *window = sender();
    if (m_releasingWindows.contains(window))
        return;
    forgetWindow(window);
    destroyReleasedWindow(window);
}

void NativeChildWindowManager::forgetWindow(QObject *window) {
    if (!window)
        return;
    const QString key = m_keysByWindow.take(window);
    if (!key.isEmpty())
        m_windowsByKey.remove(key);
}

void NativeChildWindowManager::requestWindowClose(QObject *window) {
    if (!window)
        return;
    if (m_releasingWindows.contains(window))
        return;
    if (!QMetaObject::invokeMethod(window, "requestCloseFromController", Qt::DirectConnection))
        QMetaObject::invokeMethod(window, "close", Qt::QueuedConnection);
}

void NativeChildWindowManager::destroyReleasedWindow(QObject *window) {
    if (!window)
        return;
    if (m_releasingWindows.contains(window))
        return;
    m_releasingWindows.insert(window);
    auto guarded = QPointer<QObject>(window);
    QMetaObject::invokeMethod(this, [this, guarded]() {
        if (!guarded)
            return;
        QMetaObject::invokeMethod(guarded.data(), "releaseContent", Qt::DirectConnection);
        QMetaObject::invokeMethod(guarded.data(), "cleanupExternalShadow", Qt::DirectConnection);
        if (auto *quickWindow = qobject_cast<QQuickWindow *>(guarded.data())) {
            quickWindow->hide();
            quickWindow->releaseResources();
        }
        guarded->deleteLater();
        QCoreApplication::sendPostedEvents(guarded.data(), QEvent::DeferredDelete);
        QTimer::singleShot(2000, this, [this, guarded]() {
            if (!guarded)
                return;
            m_releasingWindows.remove(guarded.data());
        });
    }, Qt::QueuedConnection);
}

#include "native_child_window_manager.moc"
