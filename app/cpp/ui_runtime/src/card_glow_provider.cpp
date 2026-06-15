#include "card_glow_provider.h"

#include <QColor>
#include <QMutexLocker>
#include <QPainter>
#include <QPainterPath>
#include <QRectF>
#include <QtMath>
#include <algorithm>

namespace {

int safeInt(const QString &value, int fallback)
{
    bool ok = false;
    const int result = value.toDouble(&ok);
    return ok ? result : fallback;
}

double safeFloat(const QString &value, double fallback)
{
    bool ok = false;
    const double result = value.toDouble(&ok);
    return ok ? result : fallback;
}

std::pair<double, double> safeScalePair(const QString &value)
{
    if (value.contains(u'x')) {
        const QStringList parts = value.split(u'x', Qt::KeepEmptyParts);
        return {safeFloat(parts.value(0), 1.0), safeFloat(parts.value(1), 1.0)};
    }
    const double scale = safeFloat(value, 1.0);
    return {scale, scale};
}

double clampedScale(double value)
{
    return std::clamp(value, 0.25, 1.0);
}

int scaledPx(int value, double scale)
{
    return std::max(1, qRound(value * clampedScale(scale)));
}

double lowResolutionOpacityCompensation(double scale)
{
    return std::min(1.10, 1.0 + (1.0 - clampedScale(scale)) * 0.14);
}

QColor normalizeColor(const QString &color)
{
    QColor qcolor(QStringLiteral("#") + color.mid(0, 6).remove(u'#'));
    return qcolor.isValid() ? qcolor : QColor(QStringLiteral("#537FCD"));
}

int mixChannel(int value, int target, double ratio)
{
    ratio = std::clamp(ratio, 0.0, 1.0);
    return int(value * (1.0 - ratio) + target * ratio);
}

QColor tintColor(const QColor &color, const QString &mode, bool rim)
{
    if (mode == QLatin1String("light")) {
        const double ratio = rim ? 0.94 : 0.88;
        return QColor(
            mixChannel(color.red(), 255, ratio),
            mixChannel(color.green(), 255, ratio),
            mixChannel(color.blue(), 255, ratio),
            255);
    }
    const double ratio = rim ? 0.62 : 0.30;
    return QColor(
        mixChannel(color.red(), 235, ratio),
        mixChannel(color.green(), 242, ratio),
        mixChannel(color.blue(), 255, ratio),
        255);
}

QImage glowTemplate()
{
    static const QImage cached = [] {
        const int width = 384;
        const int height = 144;
        QImage image(width, height, QImage::Format_ARGB32);
        image.fill(Qt::transparent);
        for (int y = 0; y < height; ++y) {
            const double yn = double(height - 1 - y) / double(height - 1);
            for (int x = 0; x < width; ++x) {
                const double xn = double(x) / double(width - 1);
                const double lowerEdge = std::exp(-std::pow((xn - 0.42) / 0.88, 2.0) - std::pow(yn / 0.075, 2.0));
                const double leftPool = std::exp(-std::pow((xn - 0.11) / 0.42, 2.0) - std::pow(yn / 0.54, 2.0));
                const double broadWash = std::exp(-std::pow((xn - 0.32) / 0.74, 2.0) - std::pow(yn / 0.35, 2.0));
                const double value = 0.34 * lowerEdge + 0.43 * leftPool + 0.38 * broadWash;
                const int alpha = int(118 * std::pow(std::min(1.0, value), 1.62) + 22 * lowerEdge);
                if (alpha > 0)
                    image.setPixelColor(x, y, QColor(255, 255, 255, std::min(255, alpha)));
            }
        }
        return image;
    }();
    return cached;
}

QImage rimTemplate()
{
    static const QImage cached = [] {
        const int width = 384;
        const int height = 12;
        QImage image(width, height, QImage::Format_ARGB32);
        image.fill(Qt::transparent);
        for (int y = 0; y < height; ++y) {
            const double yn = double(y) / double(height - 1);
            for (int x = 0; x < width; ++x) {
                const double xn = double(x) / double(width - 1);
                const double along = std::exp(-std::pow((xn - 0.30) / 0.24, 2.0));
                const double thickness = 0.014 + 0.034 * along;
                const double cross = std::exp(-std::pow(std::abs(yn - 0.92) / thickness, 2.0));
                const int alpha = int(235 * std::pow(along, 0.72) * cross);
                if (alpha > 0)
                    image.setPixelColor(x, y, QColor(255, 255, 255, std::min(255, alpha)));
            }
        }
        return image;
    }();
    return cached;
}

QImage sideGlowTemplate(int width, int height, const QString &mode)
{
    width = std::clamp(width, 1, 96);
    height = std::clamp(height, 1, 1400);
    QImage image(width, height, QImage::Format_ARGB32);
    image.fill(Qt::transparent);
    const int strength = mode == QLatin1String("light") ? 82 : 72;

    for (int y = 0; y < height; ++y) {
        const double yn = double(y) / double(std::max(1, height - 1));
        const double center = std::exp(-std::pow((yn - 0.50) / 0.38, 2.0));
        const double upper = std::exp(-std::pow((yn - 0.18) / 0.30, 2.0)) * 0.24;
        const double lower = std::exp(-std::pow((yn - 0.84) / 0.34, 2.0)) * 0.30;
        const double vertical = std::min(1.0, 0.16 + 0.78 * center + upper + lower);
        const double glowWidth = 0.28 + 0.30 * vertical;

        for (int x = 0; x < width; ++x) {
            const double distance = double(width - 1 - x) / double(std::max(1, width - 1));
            const double broad = std::exp(-std::pow(distance / glowWidth, 2.0));
            const int alpha = int(strength * vertical * std::pow(broad, 1.32));
            if (alpha > 0)
                image.setPixelColor(x, y, QColor(255, 255, 255, std::min(255, alpha)));
        }
    }
    return image;
}

QImage sideRimTemplate(int width, int height, const QString &mode)
{
    width = std::clamp(width, 1, 96);
    height = std::clamp(height, 1, 1400);
    QImage image(width, height, QImage::Format_ARGB32);
    image.fill(Qt::transparent);
    const int strength = mode == QLatin1String("light") ? 160 : 148;

    for (int y = 0; y < height; ++y) {
        const double yn = double(y) / double(std::max(1, height - 1));
        const double center = std::exp(-std::pow((yn - 0.50) / 0.38, 2.0));
        const double upper = std::exp(-std::pow((yn - 0.18) / 0.30, 2.0)) * 0.24;
        const double lower = std::exp(-std::pow((yn - 0.84) / 0.34, 2.0)) * 0.30;
        const double vertical = std::min(1.0, 0.16 + 0.78 * center + upper + lower);
        const double rimWidth = 0.010 + 0.028 * std::pow(vertical, 1.16);

        for (int x = 0; x < width; ++x) {
            const double distance = double(width - 1 - x) / double(std::max(1, width - 1));
            const double rim = std::exp(-std::pow(distance / rimWidth, 2.0));
            const int alpha = int(strength * std::pow(vertical, 0.78) * std::pow(rim, 0.92));
            if (alpha > 0)
                image.setPixelColor(x, y, QColor(255, 255, 255, std::min(255, alpha)));
        }
    }
    return image;
}

QImage tintTemplate(const QImage &source, const QColor &color, const QString &mode, bool rim)
{
    QImage image = source.copy();
    QPainter painter(&image);
    painter.setCompositionMode(QPainter::CompositionMode_SourceIn);
    painter.fillRect(image.rect(), tintColor(color, mode, rim));
    painter.end();
    return image;
}

} // namespace

CardGlowProvider::CardGlowProvider()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
}

void CardGlowProvider::clearCache()
{
    QMutexLocker locker(&m_cacheMutex);
    m_cache.clear();
    m_cacheOrder.clear();
}

QImage CardGlowProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    const QStringList parts = id.split(u'/', Qt::SkipEmptyParts);
    const QString kind = parts.value(0, QStringLiteral("card"));
    const QString mode = parts.value(1, QStringLiteral("light"));
    const QColor color = normalizeColor(parts.value(2, QStringLiteral("537FCD")));
    const int radius = safeInt(parts.value(3), 12);
    const auto [renderScaleX, renderScaleY] = safeScalePair(parts.value(5, QStringLiteral("1.0")));
    const int width = requestedSize.width() > 0 ? requestedSize.width() : 384;
    const int height = requestedSize.height() > 0 ? requestedSize.height() : 160;
    const QString cacheKey = QStringLiteral("%1/%2/%3/%4/%5x%6/%7x%8")
        .arg(kind, mode, color.name(QColor::HexRgb).mid(1).toUpper())
        .arg(radius)
        .arg(width)
        .arg(height)
        .arg(renderScaleX, 0, 'f', 3)
        .arg(renderScaleY, 0, 'f', 3);

    QImage image = cachedImage(cacheKey);
    if (!image.isNull()) {
        if (size)
            *size = image.size();
        return image;
    }

    // Reuse generated images during live resize; otherwise every bucket hit
    // reruns pixel-level glow generation and stalls Qt Quick content.
    image = kind == QLatin1String("side")
        ? renderSide(mode, color, std::max(1, width), std::max(1, height), renderScaleX, renderScaleY)
        : renderCard(mode, color, std::max(1, width), std::max(1, height), std::max(0, radius), renderScaleX, renderScaleY);
    insertCachedImage(cacheKey, image);
    if (size)
        *size = image.size();
    return image;
}

QImage CardGlowProvider::cachedImage(const QString &key) const
{
    QMutexLocker locker(&m_cacheMutex);
    const auto it = m_cache.constFind(key);
    return it == m_cache.constEnd() ? QImage() : it.value();
}

void CardGlowProvider::insertCachedImage(const QString &key, const QImage &image) const
{
    constexpr int maxEntries = 10;
    QMutexLocker locker(&m_cacheMutex);
    if (m_cache.contains(key))
        return;
    m_cache.insert(key, image);
    m_cacheOrder.append(key);
    while (m_cacheOrder.size() > maxEntries) {
        const QString oldest = m_cacheOrder.takeFirst();
        m_cache.remove(oldest);
    }
}

QImage CardGlowProvider::renderCard(
    const QString &mode,
    const QColor &primary,
    int width,
    int height,
    int radius,
    double renderScaleX,
    double renderScaleY) const
{
    width = std::clamp(width, 1, 1400);
    height = std::clamp(height, 1, 700);
    radius = std::clamp(radius, 0, 80);
    renderScaleX = clampedScale(renderScaleX);
    renderScaleY = clampedScale(renderScaleY);

    QImage image(width, height, QImage::Format_ARGB32);
    image.fill(Qt::transparent);
    QPainter painter(&image);
    painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter.setRenderHint(QPainter::Antialiasing, true);

    const QImage glow = tintTemplate(glowTemplate(), primary, mode, false);
    const QImage rim = tintTemplate(rimTemplate(), primary, mode, true);

    const int glowH = std::max(scaledPx(72, renderScaleY), std::min(int(height * 0.70), scaledPx(220, renderScaleY)));
    painter.setOpacity(mode == QLatin1String("light") ? 1.0 : 0.69);
    painter.drawImage(QRectF(0, height - glowH, width, glowH), glow);

    const int topGlowH = std::max(scaledPx(72, renderScaleY), std::min(int(height * 0.52), scaledPx(210, renderScaleY)));
    painter.setOpacity(mode == QLatin1String("light") ? 0.90 : 0.51);
    painter.drawImage(QRectF(0, 0, width, topGlowH), glow.mirrored(true, true));

    const int rimH = std::max(scaledPx(5, renderScaleY), std::min(scaledPx(12, renderScaleY), int(height * 0.045)));
    const int rimLeft = std::max(scaledPx(10, renderScaleX), radius + scaledPx(5, renderScaleX));
    const int rimRight = std::max(scaledPx(28, renderScaleX), radius + scaledPx(24, renderScaleX));
    painter.setOpacity(1.0);
    painter.drawImage(QRectF(rimLeft, height - rimH, std::max(1, width - rimLeft - rimRight), rimH), rim);

    const int topRimW = std::max(scaledPx(96, renderScaleX), std::min(int(width * 0.48), scaledPx(360, renderScaleX)));
    const int topRimH = std::max(scaledPx(4, renderScaleY), std::min(scaledPx(9, renderScaleY), int(height * 0.035)));
    const int topRimX = std::max(radius + scaledPx(8, renderScaleX), width - topRimW - radius - scaledPx(4, renderScaleX));
    painter.drawImage(QRectF(topRimX, 0, topRimW, topRimH), rim.mirrored(true, true));

    painter.setCompositionMode(QPainter::CompositionMode_DestinationIn);
    QImage maskImage(width, height, QImage::Format_ARGB32);
    maskImage.fill(Qt::transparent);
    QPainter maskPainter(&maskImage);
    maskPainter.setRenderHint(QPainter::Antialiasing, true);
    QPainterPath mask;
    mask.addRoundedRect(QRectF(0, 0, width, height), radius + 1, radius + 1);
    maskPainter.fillPath(mask, QColor(255, 255, 255, 255));
    maskPainter.end();
    painter.drawImage(0, 0, maskImage);
    painter.end();
    return image;
}

QImage CardGlowProvider::renderSide(
    const QString &mode,
    const QColor &primary,
    int width,
    int height,
    double renderScaleX,
    double renderScaleY) const
{
    width = std::clamp(width, 1, 96);
    height = std::clamp(height, 1, 1400);
    renderScaleX = clampedScale(renderScaleX);
    renderScaleY = clampedScale(renderScaleY);

    QImage image(width, height, QImage::Format_ARGB32);
    image.fill(Qt::transparent);

    QPainter painter(&image);
    painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter.setRenderHint(QPainter::Antialiasing, true);
    const double opacityCompensation = lowResolutionOpacityCompensation(std::min(renderScaleX, renderScaleY));
    painter.setOpacity(opacityCompensation * 0.5);
    painter.drawImage(0, 0, tintTemplate(sideGlowTemplate(width, height, mode), primary, mode, false));
    painter.setOpacity(opacityCompensation);
    painter.drawImage(0, 0, tintTemplate(sideRimTemplate(width, height, mode), primary, mode, true));
    painter.end();
    return image;
}
