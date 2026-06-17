#pragma once

#include <QQuickImageProvider>
#include <QColor>
#include <QHash>
#include <QImage>
#include <QMutex>
#include <QSize>
#include <QStringList>

class CardGlowProvider final : public QQuickImageProvider {
public:
    CardGlowProvider();
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
    void clearCache();

private:
    QImage renderCard(const QString &mode, const QColor &primary, int width, int height, int radius, double renderScaleX, double renderScaleY) const;
    QImage renderSide(const QString &mode, const QColor &primary, int width, int height, double renderScaleX, double renderScaleY) const;
    QImage cachedImage(const QString &key) const;
    void insertCachedImage(const QString &key, const QImage &image) const;

    mutable QMutex m_cacheMutex;
    mutable QHash<QString, QImage> m_cache;
    mutable QStringList m_cacheOrder;
};
