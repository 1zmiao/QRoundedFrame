#pragma once

#include <QtCore/QEvent>
#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QSize>
#include <QtCore/QUrl>
#include <QtQml/qqmlregistration.h>
#include <QtQuick/QQuickItem>
#include <QtQuick/QQuickWindow>

#include <QWKQuick/quickwindowagent.h>

class NativeWindowAgent : public QWK::QuickWindowAgent {
    Q_OBJECT
    QML_ELEMENT

public:
    explicit NativeWindowAgent(QObject *parent = nullptr);
    ~NativeWindowAgent() override;

    Q_INVOKABLE void setup(QQuickWindow *window);
    Q_INVOKABLE void setTitleBar(QQuickItem *item);
    Q_INVOKABLE void setSystemButton(const QString &role, QQuickItem *item);
    Q_INVOKABLE void setHitTestVisible(QQuickItem *item, bool visible);
    Q_INVOKABLE void setCustomShadowEnabled(bool enabled);
    Q_INVOKABLE void setCornerRadius(int radius);
    Q_INVOKABLE void setShadowAsset(const QUrl &source, int margin, qreal opacity);
    Q_INVOKABLE bool isMaximized(QQuickWindow *window) const;

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    static int systemButtonRole(const QString &role);
    void applyWindowAttributes();
    void applyWindowRegion(bool redraw = true);
    void clearWindowRegion();

    QPointer<QQuickWindow> m_window;
    bool m_customShadow = false;
    int m_cornerRadius = 0;
    QSize m_lastRegionSize;
    int m_lastRegionRadius = -1;
    QUrl m_shadowSource;
    int m_shadowMargin = 0;
    qreal m_shadowOpacity = 1.0;
};
