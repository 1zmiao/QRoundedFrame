#include "runtime_app.h"

#include "card_glow_provider.h"
#include "task_store.h"

#include <QApplication>
#include <QCoreApplication>
#include <QClipboard>
#include <QColor>
#include <QCursor>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QQmlEngine>
#include <QJSValue>
#include <QQuickWindow>
#include <QProcess>
#include <QProcessEnvironment>
#include <QScreen>
#include <QSaveFile>
#include <QTimer>
#include <QVector>
#include <QFont>
#include <QFocusEvent>
#include <QFontInfo>
#include <QIcon>
#include <QMenu>
#include <QMouseEvent>
#include <QPainter>
#include <QPainterPath>
#include <QSystemTrayIcon>
#include <QWidget>
#include <QtConcurrent/QtConcurrentRun>

#include <cmath>
#include <cstdlib>
#include <cstring>

#ifdef Q_OS_WIN
#include <windows.h>
#include <windowsx.h>
#include <wincrypt.h>
#include <psapi.h>
#include <pdh.h>
#include <pdhmsg.h>
#include <shellapi.h>
#include <dwmapi.h>
#include <winternl.h>
#elif defined(Q_OS_UNIX)
#include <unistd.h>
#endif

#if defined(Q_OS_LINUX) && defined(QROUNDEDFRAME_HAS_LIBSECRET)
#include <libsecret/secret.h>
#endif

namespace {

QString desktopText()
{
    return QStringList{
        QString::fromLocal8Bit(qgetenv("XDG_CURRENT_DESKTOP")),
        QString::fromLocal8Bit(qgetenv("XDG_SESSION_DESKTOP")),
        QString::fromLocal8Bit(qgetenv("DESKTOP_SESSION")),
    }.join(u';').toLower();
}

bool isKdeDesktop()
{
#ifdef Q_OS_LINUX
    const QString desktop = desktopText();
    return desktop.contains(QStringLiteral("kde")) || desktop.contains(QStringLiteral("plasma"));
#else
    return false;
#endif
}

double readKdeScreenScale()
{
#ifdef Q_OS_LINUX
    if (!isKdeDesktop())
        return 0.0;
    QFile file(QDir::homePath() + QStringLiteral("/.config/kdeglobals"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return 0.0;

    bool inKScreen = false;
    QString screenScaleFactors;
    while (!file.atEnd()) {
        const QString line = QString::fromUtf8(file.readLine()).trimmed();
        if (line.isEmpty() || line.startsWith(u'#') || line.startsWith(u';'))
            continue;
        if (line.startsWith(u'[') && line.endsWith(u']')) {
            inKScreen = line.mid(1, line.size() - 2) == QStringLiteral("KScreen");
            continue;
        }
        if (!inKScreen)
            continue;
        const int equals = line.indexOf(u'=');
        if (equals <= 0)
            continue;
        const QString key = line.left(equals);
        const QString value = line.mid(equals + 1).trimmed();
        if (key == QStringLiteral("ScaleFactor")) {
            bool ok = false;
            const double scale = value.toDouble(&ok);
            if (ok && scale > 0.0)
                return qMax(1.0, scale);
        } else if (key == QStringLiteral("ScreenScaleFactors")) {
            screenScaleFactors = value;
        }
    }

    const QStringList parts = screenScaleFactors.split(u';', Qt::SkipEmptyParts);
    for (const QString &part : parts) {
        const int equals = part.lastIndexOf(u'=');
        if (equals < 0)
            continue;
        bool ok = false;
        const double scale = part.mid(equals + 1).toDouble(&ok);
        if (ok && scale > 0.0)
            return qMax(1.0, scale);
    }
#endif
    return 0.0;
}

double readQtScreenDpr()
{
    QScreen *screen = QGuiApplication::primaryScreen();
    return screen ? qMax(1.0, screen->devicePixelRatio()) : 1.0;
}

double readContentUiScale()
{
#ifdef Q_OS_LINUX
    const double kdeScale = readKdeScreenScale();
    if (kdeScale > 0.0)
        return qBound(0.5, kdeScale / readQtScreenDpr(), 2.5);
#endif
    return 1.0;
}

} // namespace

#if defined(Q_OS_LINUX) && defined(QROUNDEDFRAME_HAS_X11)
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#endif

namespace {

QColor mixColor(const QColor &a, const QColor &b, double t)
{
    t = qBound(0.0, t, 1.0);
    return QColor(
        int(std::lround(a.red() * (1.0 - t) + b.red() * t)),
        int(std::lround(a.green() * (1.0 - t) + b.green() * t)),
        int(std::lround(a.blue() * (1.0 - t) + b.blue() * t)),
        int(std::lround(a.alpha() * (1.0 - t) + b.alpha() * t)));
}

QColor parseColor(const QString &text, const QColor &fallback)
{
    const QColor color(text);
    return color.isValid() ? color : fallback;
}

#ifdef Q_OS_WIN
constexpr int kTrayPopupWidth = 184;
constexpr int kTrayPopupItemHeight = 38;
constexpr int kTrayPopupSeparatorHeight = 1;
constexpr int kTrayPopupPadding = 9;
constexpr int kTrayPopupRadius = 10;

COLORREF colorRef(const QColor &color)
{
    return RGB(color.red(), color.green(), color.blue());
}
#endif

QVariantMap defaultSettings()
{
    return {
        {QStringLiteral("ui"), QVariantMap{
            {QStringLiteral("lastPage"), QStringLiteral("home")},
            {QStringLiteral("showColorButton"), true},
            {QStringLiteral("showTitleBarResourceStats"), false},
            {QStringLiteral("showTitleBarCpu"), false},
            {QStringLiteral("showTitleBarMemory"), false},
            {QStringLiteral("showTitleBarGpu"), false},
            {QStringLiteral("fontScale"), 1.0},
        }},
        {QStringLiteral("layout"), QVariantMap{
            {QStringLiteral("navWidth"), 46.0},
        }},
        {QStringLiteral("theme"), QVariantMap{
            {QStringLiteral("mode"), QStringLiteral("dark")},
            {QStringLiteral("primaryColor"), QStringLiteral("#1D38AC")},
            {QStringLiteral("lightPrimaryColor"), QStringLiteral("#5886D9")},
            {QStringLiteral("darkPrimaryColor"), QStringLiteral("#1D38AC")},
        }},
        {QStringLiteral("window"), QVariantMap{
            {QStringLiteral("closeToTray"), false},
            {QStringLiteral("minimizeToTray"), false},
        }},
    };
}

QVariant nestedValue(const QVariantMap &root, const QString &key, const QVariant &fallback)
{
    QVariant cur = root;
    const auto parts = key.split(u'/', Qt::SkipEmptyParts);
    for (const QString &part : parts) {
        if (!cur.canConvert<QVariantMap>())
            return fallback;
        const QVariantMap map = cur.toMap();
        if (!map.contains(part))
            return fallback;
        cur = map.value(part);
    }
    return cur.isValid() ? cur : fallback;
}

QVariantMap setNestedValueRecursive(QVariantMap root, const QStringList &parts, int index, const QVariant &value)
{
    if (index >= parts.size())
        return root;
    if (index == parts.size() - 1) {
        root.insert(parts.at(index), value);
        return root;
    }
    QVariantMap child = root.value(parts.at(index)).toMap();
    root.insert(parts.at(index), setNestedValueRecursive(child, parts, index + 1, value));
    return root;
}

bool removeNestedValueRecursive(QVariantMap &root, const QStringList &parts, int index)
{
    if (index >= parts.size())
        return false;
    if (index == parts.size() - 1)
        return root.remove(parts.at(index)) > 0;
    QVariant childValue = root.value(parts.at(index));
    if (!childValue.canConvert<QVariantMap>())
        return false;
    QVariantMap child = childValue.toMap();
    const bool removed = removeNestedValueRecursive(child, parts, index + 1);
    if (removed)
        root.insert(parts.at(index), child);
    return removed;
}

QVariantMap variantMapFromAny(const QVariant &value)
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

QVariant jsonSafeVariantFromAny(const QVariant &value)
{
    QVariant normalized = value;
    if (value.canConvert<QJSValue>()) {
        const QJSValue js = value.value<QJSValue>();
        normalized = js.toVariant();
    }

    const QJsonValue jsonValue = QJsonValue::fromVariant(normalized);
    return jsonValue.toVariant();
}

#if defined(Q_OS_LINUX) && defined(QROUNDEDFRAME_HAS_LIBSECRET)
const SecretSchema *runtimeSecretSchema()
{
    static const SecretSchema schema = {
        "local.qroundedframe.RuntimeSecrets",
        SECRET_SCHEMA_NONE,
        {
            {"app", SECRET_SCHEMA_ATTRIBUTE_STRING},
            {"name", SECRET_SCHEMA_ATTRIBUTE_STRING},
            {nullptr, SECRET_SCHEMA_ATTRIBUTE_STRING},
        }
    };
    return &schema;
}

QByteArray readSecretServiceVault()
{
    GError *error = nullptr;
    gchar *password = secret_password_lookup_sync(
        runtimeSecretSchema(),
        nullptr,
        &error,
        "app", "QRoundedFrame",
        "name", "RuntimeSecrets",
        nullptr);
    if (error) {
        qWarning() << "RuntimeSecrets libsecret lookup failed" << QString::fromUtf8(error->message);
        g_error_free(error);
        return {};
    }
    if (!password)
        return {};
    const QByteArray payload(password);
    secret_password_free(password);
    return payload;
}

bool writeSecretServiceVault(const QByteArray &payload)
{
    GError *error = nullptr;
    const gboolean ok = secret_password_store_sync(
        runtimeSecretSchema(),
        SECRET_COLLECTION_DEFAULT,
        "QRoundedFrame secrets",
        payload.constData(),
        nullptr,
        &error,
        "app", "QRoundedFrame",
        "name", "RuntimeSecrets",
        nullptr);
    if (error) {
        qWarning() << "RuntimeSecrets libsecret store failed" << QString::fromUtf8(error->message);
        g_error_free(error);
        return false;
    }
    return ok == TRUE;
}
#endif

bool envFlag(const char *name)
{
    const QByteArray value = qgetenv(name).trimmed().toLower();
    return value == "1" || value == "true" || value == "yes" || value == "on";
}

#ifdef Q_OS_WIN
using RtlGetVersionFunction = LONG(WINAPI *)(PRTL_OSVERSIONINFOW);

int windowsBuildNumber()
{
    RTL_OSVERSIONINFOW info = {};
    info.dwOSVersionInfoSize = sizeof(info);
    const HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    if (!ntdll)
        return 0;
    auto rtlGetVersion = reinterpret_cast<RtlGetVersionFunction>(GetProcAddress(ntdll, "RtlGetVersion"));
    if (!rtlGetVersion || rtlGetVersion(&info) != 0)
        return 0;
    return static_cast<int>(info.dwBuildNumber);
}

bool textContainsAny(const QString &text, const QStringList &markers)
{
    const QString lower = text.toLower();
    for (const QString &marker : markers) {
        if (lower.contains(marker))
            return true;
    }
    return false;
}

bool windowsDisplayFallbackNeeded(bool isWin11OrNewer)
{
    if (envFlag("FRAMELESS_ASSUME_SYSTEM_CORNERS"))
        return false;

    QStringList texts;
    for (DWORD index = 0; index < 16; ++index) {
        DISPLAY_DEVICEW device = {};
        device.cb = sizeof(device);
        if (!EnumDisplayDevicesW(nullptr, index, &device, 0))
            break;
        texts << QString::fromWCharArray(device.DeviceName)
              << QString::fromWCharArray(device.DeviceString)
              << QString::fromWCharArray(device.DeviceID);
    }

    const QString joined = texts.join(u' ');
    if (textContainsAny(joined, {
            QStringLiteral("microsoft basic display"),
        })) {
        return true;
    }

    if (isWin11OrNewer && !envFlag("FRAMELESS_WINDOWS_VM_CUSTOM_CHROME"))
        return false;

    return textContainsAny(joined, {
        QStringLiteral("vmware"),
        QStringLiteral("virtualbox"),
        QStringLiteral("hyper-v"),
        QStringLiteral("parallels"),
        QStringLiteral("virtio"),
        QStringLiteral("qxl"),
    });
}
#endif

#ifdef Q_OS_LINUX
QString linuxEnvText(const char *name)
{
    return QString::fromLocal8Bit(qgetenv(name)).trimmed().toLower();
}

bool linuxTextContainsAny(const QString &text, const QStringList &tokens)
{
    if (text.isEmpty())
        return false;
    for (const QString &token : tokens) {
        if (!token.isEmpty() && text.contains(token))
            return true;
    }
    return false;
}

QString linuxSessionType()
{
    const QString session = linuxEnvText("XDG_SESSION_TYPE");
    if (!session.isEmpty())
        return session;
    if (!linuxEnvText("WAYLAND_DISPLAY").isEmpty())
        return QStringLiteral("wayland");
    if (!linuxEnvText("DISPLAY").isEmpty())
        return QStringLiteral("x11");
    return {};
}

QString linuxDesktopText()
{
    QStringList values;
    for (const char *name : {"XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "DESKTOP_SESSION", "WINDOW_MANAGER"}) {
        const QString value = linuxEnvText(name);
        if (!value.isEmpty())
            values << value;
    }
    return values.join(u';');
}

bool linuxCustomChromeAllowlisted(const QString &desktopText)
{
    QStringList tokens = {
        QStringLiteral("gnome"), // GNOME on Xorg / Mutter verified.
        QStringLiteral("cinnamon"), // Cinnamon on X11 / Muffin verified.
        QStringLiteral("mate"), // MATE on X11 / Marco verified.
        QStringLiteral("xfce"), // XFCE on X11 / Xfwm4 verified.
        QStringLiteral("kde"), // KDE Plasma on X11 verified.
        QStringLiteral("plasma"), // KDE Plasma session token used by some distributions.
    };
    const QString extra = linuxEnvText("FRAMELESS_LINUX_CUSTOM_CHROME_WM");
    if (!extra.isEmpty()) {
        QString normalized = extra;
        normalized.replace(u';', u' ');
        normalized.replace(u',', u' ');
        normalized.replace(u'|', u' ');
        tokens << normalized.split(u' ', Qt::SkipEmptyParts);
    }
    return linuxTextContainsAny(desktopText, tokens);
}

bool linuxDesktopIsXfce()
{
    return linuxTextContainsAny(linuxDesktopText(), {QStringLiteral("xfce")});
}

bool linuxDesktopNeedsSystemTrayMenu()
{
    return linuxTextContainsAny(linuxDesktopText(), {
        QStringLiteral("xfce"),
        QStringLiteral("kde"),
        QStringLiteral("plasma"),
    });
}

#endif

void setNestedValue(QVariantMap &root, const QString &key, const QVariant &value)
{
    const auto parts = key.split(u'/', Qt::SkipEmptyParts);
    if (!parts.isEmpty())
        root = setNestedValueRecursive(root, parts, 0, value);
}

QString pageTitleFor(const QString &key)
{
    if (key == QLatin1String("settings")) return QStringLiteral("设置");
    if (key == QLatin1String("tools")) return QStringLiteral("工具");
    if (key == QLatin1String("update")) return QStringLiteral("更新");
    if (key == QLatin1String("about")) return QStringLiteral("关于");
    if (key == QLatin1String("inline-demo")) return QStringLiteral("页内子窗口");
    if (key == QLatin1String("task-create")) return QStringLiteral("新建任务");
    if (key == QLatin1String("task-edit")) return QStringLiteral("编辑任务");
    return QStringLiteral("主页");
}

QString pageSourceFor(const QString &key)
{
    if (key == QLatin1String("settings")) return QStringLiteral("../pages/SettingsPage.qml");
    if (key == QLatin1String("tools")) return QStringLiteral("../pages/ToolsPage.qml");
    if (key == QLatin1String("update")) return QStringLiteral("../pages/UpdatePage.qml");
    if (key == QLatin1String("about")) return QStringLiteral("../pages/AboutPage.qml");
    if (key == QLatin1String("inline-demo")) return QStringLiteral("../pages/InlineDemoPage.qml");
    if (key == QLatin1String("task-create")) return QStringLiteral("../pages/TaskCreatePage.qml");
    if (key == QLatin1String("task-edit")) return QStringLiteral("../pages/TaskEditPage.qml");
    return QStringLiteral("../pages/HomePage.qml");
}

QString pageIconFor(const QString &key)
{
    if (key == QLatin1String("settings")) return QStringLiteral("settings");
    if (key == QLatin1String("tools")) return QStringLiteral("tools");
    if (key == QLatin1String("update")) return QStringLiteral("update");
    if (key == QLatin1String("about")) return QStringLiteral("about");
    if (key == QLatin1String("inline-demo")) return QStringLiteral("dialog");
    return QStringLiteral("home");
}

QString absolutePagePathFor(const QString &rootPath, const QString &key)
{
    const QDir windowDir(QDir(rootPath).absoluteFilePath(QStringLiteral("qml/window")));
    return QDir::cleanPath(windowDir.absoluteFilePath(pageSourceFor(key)));
}

double bytesToMb(qulonglong bytes)
{
    return double(bytes) / 1024.0 / 1024.0;
}

#ifdef Q_OS_WIN
quint64 fileTimeToUInt64(const FILETIME &time)
{
    ULARGE_INTEGER value = {};
    value.LowPart = time.dwLowDateTime;
    value.HighPart = time.dwHighDateTime;
    return value.QuadPart;
}
#endif

#ifdef Q_OS_LINUX
double kbToMb(qulonglong kb)
{
    return double(kb) / 1024.0;
}

QVariantMap linuxMemorySampleFromSmapsRollup()
{
    QFile file(QStringLiteral("/proc/self/smaps_rollup"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};

    QHash<QString, qulonglong> values;
    const QList<QByteArray> lines = file.readAll().split('\n');
    for (const QByteArray &line : lines) {
        const int colon = line.indexOf(':');
        if (colon <= 0)
            continue;
        const QByteArray keyBytes = line.left(colon).trimmed();
        const QByteArray rawValue = line.mid(colon + 1).trimmed();
        if (keyBytes.isEmpty() || rawValue.isEmpty())
            continue;

        int end = 0;
        while (end < rawValue.size() && rawValue.at(end) >= '0' && rawValue.at(end) <= '9')
            ++end;
        if (end <= 0)
            continue;

        bool ok = false;
        const qulonglong value = rawValue.left(end).toULongLong(&ok);
        if (ok)
            values.insert(QString::fromLatin1(keyBytes), value);
    }

    const qulonglong rss = values.value(QStringLiteral("Rss"), 0);
    const qulonglong privateClean = values.value(QStringLiteral("Private_Clean"), 0);
    const qulonglong privateDirty = values.value(QStringLiteral("Private_Dirty"), 0);
    const qulonglong privateHugetlb = values.value(QStringLiteral("Private_Hugetlb"), 0);
    const qulonglong uss = privateClean + privateDirty + privateHugetlb;
    const qulonglong privateResident = privateDirty + privateHugetlb;
    const qulonglong pss = values.value(QStringLiteral("Pss"), 0);
    if (rss == 0 && uss == 0 && pss == 0)
        return {};

    return {
        {QStringLiteral("rss"), kbToMb(rss)},
        {QStringLiteral("private"), kbToMb(privateResident)},
        {QStringLiteral("private_clean"), kbToMb(privateClean)},
        {QStringLiteral("private_dirty"), kbToMb(privateDirty)},
        {QStringLiteral("uss"), kbToMb(uss)},
        {QStringLiteral("pss"), kbToMb(pss)},
        {QStringLiteral("ws_private"), kbToMb(privateResident)},
    };
}

QVariantMap linuxMemorySampleFromStatm()
{
    QFile file(QStringLiteral("/proc/self/statm"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    const QList<QByteArray> parts = file.readAll().simplified().split(' ');
    if (parts.size() < 2)
        return {};
    bool ok = false;
    const qulonglong residentPages = parts.at(1).toULongLong(&ok);
    if (!ok)
        return {};
    const long pageSize = sysconf(_SC_PAGE_SIZE);
    const double rssMb = pageSize > 0 ? bytesToMb(residentPages * qulonglong(pageSize)) : 0.0;
    return {
        {QStringLiteral("rss"), rssMb},
        {QStringLiteral("private"), 0.0},
        {QStringLiteral("uss"), 0.0},
        {QStringLiteral("pss"), 0.0},
        {QStringLiteral("ws_private"), 0.0},
    };
}
#endif

int totalPhysicalMemoryMb()
{
#ifdef Q_OS_WIN
    MEMORYSTATUSEX status = {};
    status.dwLength = sizeof(status);
    if (GlobalMemoryStatusEx(&status))
        return int(status.ullTotalPhys / 1024 / 1024);
#elif defined(Q_OS_UNIX)
    const long pages = sysconf(_SC_PHYS_PAGES);
    const long pageSize = sysconf(_SC_PAGE_SIZE);
    if (pages > 0 && pageSize > 0)
        return int((qint64(pages) * qint64(pageSize)) / 1024 / 1024);
#endif
    return 0;
}

#ifdef Q_OS_WIN
double currentWorkingSetPrivateMb()
{
    HANDLE process = GetCurrentProcess();
    SYSTEM_INFO systemInfo;
    GetSystemInfo(&systemInfo);
    const SIZE_T pageSize = qMax<DWORD>(4096, systemInfo.dwPageSize);
    const quintptr maxAddress = reinterpret_cast<quintptr>(systemInfo.lpMaximumApplicationAddress);

    MEMORY_BASIC_INFORMATION mbi = {};
    quintptr address = 0;
    qulonglong privateWorkingSet = 0;
    QVector<PSAPI_WORKING_SET_EX_INFORMATION> entries;
    entries.reserve(8192);

    auto flushEntries = [&]() {
        if (entries.isEmpty())
            return;
        if (QueryWorkingSetEx(process, entries.data(), DWORD(entries.size() * sizeof(PSAPI_WORKING_SET_EX_INFORMATION)))) {
            for (const auto &entry : entries) {
                const ULONG_PTR flags = entry.VirtualAttributes.Flags;
                const bool valid = (flags & 0x1) != 0;
                const bool shared = ((flags >> 15) & 0x1) != 0;
                if (valid && !shared)
                    privateWorkingSet += pageSize;
            }
        }
        entries.clear();
    };

    while (address < maxAddress) {
        if (!VirtualQuery(reinterpret_cast<LPCVOID>(address), &mbi, sizeof(mbi))) {
            address += pageSize;
            continue;
        }
        const quintptr base = reinterpret_cast<quintptr>(mbi.BaseAddress);
        const quintptr regionSize = qMax<SIZE_T>(mbi.RegionSize, pageSize);
        const DWORD protect = mbi.Protect;
        if (mbi.State == MEM_COMMIT && !(protect & PAGE_GUARD) && !(protect & PAGE_NOACCESS)) {
            const quintptr end = qMin(base + regionSize, maxAddress);
            for (quintptr page = base; page < end; page += pageSize) {
                PSAPI_WORKING_SET_EX_INFORMATION info = {};
                info.VirtualAddress = reinterpret_cast<PVOID>(page);
                entries.append(info);
                if (entries.size() >= 8192)
                    flushEntries();
            }
        }
        const quintptr next = base + regionSize;
        address = next > address ? next : address + pageSize;
    }
    flushEntries();
    return bytesToMb(privateWorkingSet);
}
#endif

} // namespace

RuntimeSettings::RuntimeSettings(const QString &rootPath, QObject *parent)
    : QObject(parent)
    , m_values(defaultSettings())
{
    const QDir configDir(QDir(rootPath).absoluteFilePath(QStringLiteral("user_data/config")));
    m_filePath = configDir.absoluteFilePath(QStringLiteral("settings.json"));
    load();
    mergeDefaults(defaultSettings());
}

QVariant RuntimeSettings::valueOr(const QString &key, const QVariant &fallback) const
{
    if (key == QLatin1String("ui/lastPage")) {
        const QByteArray forcedPage = qgetenv("CPP_QTQUICK_HOME_FORCE_PAGE");
        if (!forcedPage.isEmpty())
            return QString::fromUtf8(forcedPage);
    }
    return nestedValue(m_values, key, fallback);
}

QVariant RuntimeSettings::value(const QString &key) const
{
    return valueOr(key, QVariant());
}

QString RuntimeSettings::configDir() const
{
    return QFileInfo(m_filePath).absolutePath();
}

void RuntimeSettings::setValue(const QString &key, const QVariant &value)
{
    const QVariant normalized = jsonSafeVariantFromAny(value);
    setNestedValue(m_values, key, normalized);
    save();
    ++m_revision;
    emit revisionChanged();
    emit changed(key, normalized);
}

void RuntimeSettings::remove(const QString &key)
{
    if (!removeNestedValue(key))
        return;
    save();
    ++m_revision;
    emit revisionChanged();
    emit changed(key, QVariant());
}

QString RuntimeSettings::path() const
{
    return m_filePath;
}

void RuntimeSettings::load()
{
    QFile file(m_filePath);
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (doc.isObject())
        m_values = doc.object().toVariantMap();
}

void RuntimeSettings::save() const
{
    QFileInfo info(m_filePath);
    QDir().mkpath(info.absolutePath());
    QSaveFile file(m_filePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return;
    const QJsonDocument doc(QJsonObject::fromVariantMap(m_values));
    file.write(doc.toJson(QJsonDocument::Indented));
    file.commit();
}

void RuntimeSettings::mergeDefaults(const QVariantMap &defaults)
{
    for (auto it = defaults.constBegin(); it != defaults.constEnd(); ++it) {
        if (!m_values.contains(it.key())) {
            m_values.insert(it.key(), it.value());
            continue;
        }
        if (m_values.value(it.key()).canConvert<QVariantMap>() && it.value().canConvert<QVariantMap>()) {
            QVariantMap nested = m_values.value(it.key()).toMap();
            const QVariantMap defaultNested = it.value().toMap();
            for (auto nestedIt = defaultNested.constBegin(); nestedIt != defaultNested.constEnd(); ++nestedIt) {
                if (!nested.contains(nestedIt.key()))
                    nested.insert(nestedIt.key(), nestedIt.value());
            }
            m_values.insert(it.key(), nested);
        }
    }
}

bool RuntimeSettings::removeNestedValue(const QString &key)
{
    const auto parts = key.split(u'/', Qt::SkipEmptyParts);
    if (parts.isEmpty())
        return false;
    return removeNestedValueRecursive(m_values, parts, 0);
}

RuntimeTheme::RuntimeTheme(RuntimeSettings *settings, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
{
    if (!m_settings)
        return;
    m_mode = m_settings->valueOr(QStringLiteral("theme/mode"), m_mode).toString();
    if (m_mode != QLatin1String("light") && m_mode != QLatin1String("dark"))
        m_mode = QStringLiteral("dark");
    m_lightPrimaryColor = m_settings->valueOr(QStringLiteral("theme/lightPrimaryColor"), m_settings->valueOr(QStringLiteral("theme/primaryColor"), m_lightPrimaryColor)).toString().toUpper();
    m_darkPrimaryColor = m_settings->valueOr(QStringLiteral("theme/darkPrimaryColor"), m_settings->valueOr(QStringLiteral("theme/primaryColor"), m_darkPrimaryColor)).toString().toUpper();
    m_fontScale = qBound(0.85, m_settings->valueOr(QStringLiteral("ui/fontScale"), m_fontScale).toDouble(), 1.35);
    m_showColorButton = m_settings->valueOr(QStringLiteral("ui/showColorButton"), m_showColorButton).toBool();
    refreshSystemUiScale();
    installSystemUiScaleWatcher();
}

void RuntimeTheme::installSystemUiScaleWatcher()
{
    connect(&m_systemUiScaleWatcher, &QFileSystemWatcher::fileChanged, this, [this](const QString &) {
        refreshSystemUiScaleWatcherPaths();
        refreshSystemUiScale();
    });
    connect(&m_systemUiScaleWatcher, &QFileSystemWatcher::directoryChanged, this, [this](const QString &) {
        refreshSystemUiScaleWatcherPaths();
        refreshSystemUiScale();
    });
    refreshSystemUiScaleWatcherPaths();

    const auto connectScreen = [this](QScreen *screen) {
        if (!screen)
            return;
        connect(screen, &QScreen::logicalDotsPerInchChanged, this, [this]() { refreshSystemUiScale(); });
        connect(screen, &QScreen::physicalDotsPerInchChanged, this, [this]() { refreshSystemUiScale(); });
        connect(screen, &QScreen::geometryChanged, this, [this]() { refreshSystemUiScale(); });
    };
    for (QScreen *screen : QGuiApplication::screens())
        connectScreen(screen);
    connect(qGuiApp, &QGuiApplication::screenAdded, this, connectScreen);
    connect(qGuiApp, &QGuiApplication::primaryScreenChanged, this, [this](QScreen *) {
        refreshSystemUiScale();
    });
}

void RuntimeTheme::refreshSystemUiScale()
{
    const double next = readContentUiScale();
    if (qFuzzyCompare(m_systemUiScale, next))
        return;
    m_systemUiScale = next;
    emit systemUiScaleChanged();
}

void RuntimeTheme::refreshSystemUiScaleWatcherPaths()
{
    m_kdeConfigDir = QDir::homePath() + QStringLiteral("/.config");
    m_kdeGlobalsPath = m_kdeConfigDir + QStringLiteral("/kdeglobals");
    m_kcmFontsPath = m_kdeConfigDir + QStringLiteral("/kcmfonts");

    const auto ensureWatched = [this](const QString &path, bool directory) {
        if (path.isEmpty())
            return;
        const QStringList existing = directory ? m_systemUiScaleWatcher.directories() : m_systemUiScaleWatcher.files();
        if (existing.contains(path))
            return;
        if (directory) {
            if (QDir(path).exists())
                m_systemUiScaleWatcher.addPath(path);
        } else {
            if (QFileInfo::exists(path))
                m_systemUiScaleWatcher.addPath(path);
        }
    };

    ensureWatched(m_kdeConfigDir, true);
    ensureWatched(m_kdeGlobalsPath, false);
    ensureWatched(m_kcmFontsPath, false);
}

void RuntimeTheme::setMode(const QString &mode)
{
    const QString normalized = mode == QLatin1String("light") ? QStringLiteral("light") : QStringLiteral("dark");
    if (m_mode == normalized)
        return;
    emit modeChanging(m_mode, normalized);
    m_mode = normalized;
    if (m_settings)
        m_settings->setValue(QStringLiteral("theme/mode"), m_mode);
    emit modeChanged(m_mode);
    emit primaryColorChanged(primaryColor());
}

QString RuntimeTheme::toggleMode()
{
    const QString next = m_mode == QLatin1String("dark") ? QStringLiteral("light") : QStringLiteral("dark");
    setMode(next);
    return m_mode;
}

void RuntimeTheme::setPrimaryColor(const QString &color)
{
    QColor qcolor(color);
    if (!qcolor.isValid())
        return;
    const QString normalized = qcolor.name(QColor::HexRgb).toUpper();
    QString &target = m_mode == QLatin1String("dark") ? m_darkPrimaryColor : m_lightPrimaryColor;
    const bool changed = target != normalized;
    target = normalized;
    if (m_settings) {
        m_settings->setValue(m_mode == QLatin1String("dark")
            ? QStringLiteral("theme/darkPrimaryColor")
            : QStringLiteral("theme/lightPrimaryColor"), normalized);
        m_settings->setValue(QStringLiteral("theme/primaryColor"), normalized);
    }
    if (changed)
        emit primaryColorChanged(normalized);
    emit primaryColorCommitted(normalized);
}

void RuntimeTheme::previewPrimaryColor(const QString &color)
{
    QColor qcolor(color);
    if (!qcolor.isValid())
        return;
    const QString normalized = qcolor.name(QColor::HexRgb).toUpper();
    QString &target = m_mode == QLatin1String("dark") ? m_darkPrimaryColor : m_lightPrimaryColor;
    if (target == normalized)
        return;
    target = normalized;
    emit primaryColorChanged(normalized);
}

QString RuntimeTheme::primaryColorForMode(const QString &mode) const
{
    return mode == QLatin1String("dark") ? m_darkPrimaryColor : m_lightPrimaryColor;
}

void RuntimeTheme::setFontScale(double scale)
{
    scale = qBound(0.85, scale, 1.35);
    if (qFuzzyCompare(m_fontScale, scale))
        return;
    m_fontScale = scale;
    if (m_settings)
        m_settings->setValue(QStringLiteral("ui/fontScale"), qRound(m_fontScale * 1000.0) / 1000.0);
    emit fontScaleChanged();
}

void RuntimeTheme::increaseFontScale()
{
    setFontScale(m_fontScale + 0.05);
}

void RuntimeTheme::decreaseFontScale()
{
    setFontScale(m_fontScale - 0.05);
}

void RuntimeTheme::resetFontScale()
{
    setFontScale(1.0);
}

void RuntimeTheme::setShowColorButton(bool enabled)
{
    if (m_showColorButton == enabled)
        return;
    m_showColorButton = enabled;
    if (m_settings)
        m_settings->setValue(QStringLiteral("ui/showColorButton"), enabled);
    emit showColorButtonChanged();
}

void RuntimeTheme::setRippleOrigin(double x, double y)
{
    if (qFuzzyCompare(m_rippleX, x) && qFuzzyCompare(m_rippleY, y))
        return;
    m_rippleX = x;
    m_rippleY = y;
    emit rippleOriginChanged(m_rippleX, m_rippleY);
}

bool RuntimeTheme::copyText(const QString &text)
{
    return copyToClipboard(text);
}

bool RuntimeTheme::copyToClipboard(const QString &text)
{
    QClipboard *clipboard = QGuiApplication::clipboard();
    if (!clipboard)
        return false;
    clipboard->setText(text);
    return true;
}

#ifndef Q_OS_WIN
class TrayPopupWidget final : public QWidget {
public:
    explicit TrayPopupWidget(RuntimeTray *tray, RuntimeSettings *settings)
        : QWidget(nullptr)
        , m_tray(tray)
        , m_settings(settings)
    {
        setWindowFlags((linuxDesktopIsXfce() ? Qt::Tool : Qt::Popup) | Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint);
        setAttribute(Qt::WA_TranslucentBackground, true);
        setMouseTracking(true);
        setFixedSize(kWidth + kShadow * 2, kHeight + kShadow * 2);
    }

    ~TrayPopupWidget() override
    {
        if (m_eventFilterInstalled && qApp)
            qApp->removeEventFilter(this);
    }

    void showAt(const QPoint &pos)
    {
        if (isVisible()) {
            hide();
            return;
        }
        const QRect available = screenGeometry(pos);
        int x = pos.x() - kWidth + kAnchorXOffset;
        int y = pos.y() - kHeight + kAnchorYOffset;
        if (x < available.x() + kMargin)
            x = pos.x() - kAnchorXOffset;
        if (y < available.y() + kMargin)
            y = pos.y() + kAnchorYOffset;
        x = qBound(available.x() + kMargin, x, available.right() - kWidth - kMargin + 1);
        y = qBound(available.y() + kMargin, y, available.bottom() - kHeight - kMargin + 1);
        move(x - kShadow, y - kShadow);
        m_hoverIndex = -1;
        installGlobalMouseFilter();
        show();
        raise();
        activateWindow();
    }

protected:
    void paintEvent(QPaintEvent *) override
    {
        QPainter painter(this);
        painter.setRenderHint(QPainter::Antialiasing, true);

        const QRectF panel(kShadow, kShadow, kWidth, kHeight);
        const ThemeColors colors = themeColors();

        QPainterPath shadowPath;
        shadowPath.addRoundedRect(panel.adjusted(-1, 2, 1, 3), kRadius, kRadius);
        painter.fillPath(shadowPath, QColor(0, 0, 0, colors.dark ? 90 : 38));

        QPainterPath panelPath;
        panelPath.addRoundedRect(panel, kRadius, kRadius);
        painter.fillPath(panelPath, colors.card);
        painter.setPen(QPen(colors.outline, 1));
        painter.drawPath(panelPath);

        for (int i = 0; i < 2; ++i) {
            const QRect item = itemRect(i);
            if (m_hoverIndex == i) {
                QPainterPath hoverPath;
                hoverPath.addRoundedRect(QRectF(item), 8, 8);
                painter.fillPath(hoverPath, colors.hover);
            }
        }

        const QRect first = itemRect(0);
        painter.fillRect(QRect(kShadow + kPadding, first.bottom() + 1, kWidth - kPadding * 2, 1), colors.hairline);

        QFont f = font();
        const double scale = m_settings ? m_settings->valueOr(QStringLiteral("ui/fontScale"), 1.0).toDouble() : 1.0;
        f.setPixelSize(qMax(12, int(std::lround(13.0 * qBound(0.85, scale, 1.35)))));
        painter.setFont(f);
        painter.setPen(colors.text);
        const QString labels[2] = {QStringLiteral("居中主窗口"), QStringLiteral("退出")};
        for (int i = 0; i < 2; ++i) {
            QRect textRect = itemRect(i).adjusted(30, 0, -8, 0);
            painter.drawText(textRect, Qt::AlignVCenter | Qt::AlignLeft, labels[i]);
        }
    }

    void mouseMoveEvent(QMouseEvent *event) override
    {
        const int next = indexAt(event->pos());
        if (m_hoverIndex != next) {
            m_hoverIndex = next;
            update();
        }
    }

    void leaveEvent(QEvent *) override
    {
        if (m_hoverIndex != -1) {
            m_hoverIndex = -1;
            update();
        }
    }

    void mousePressEvent(QMouseEvent *event) override
    {
        if (event->button() != Qt::LeftButton && event->button() != Qt::RightButton)
            return;
        if (indexAt(event->pos()) < 0)
            hide();
    }

    void mouseReleaseEvent(QMouseEvent *event) override
    {
        if (event->button() != Qt::LeftButton)
            return;
        const int index = indexAt(event->pos());
        hide();
        if (!m_tray)
            return;
        if (index == 0)
            m_tray->centerMainWindow();
        else if (index == 1)
            m_tray->exitApplication();
    }

    void focusOutEvent(QFocusEvent *) override
    {
        hide();
    }

    bool eventFilter(QObject *watched, QEvent *event) override
    {
        Q_UNUSED(watched)
        if (!isVisible())
            return false;
        if (event->type() != QEvent::MouseButtonPress)
            return false;
        const auto *mouse = static_cast<QMouseEvent *>(event);
        if (!frameGeometry().contains(mouse->globalPosition().toPoint()))
            hide();
        return false;
    }

private:
    struct ThemeColors {
        bool dark = true;
        QColor card;
        QColor text;
        QColor hover;
        QColor outline;
        QColor hairline;
    };

    ThemeColors themeColors() const
    {
        ThemeColors colors;
        colors.dark = m_settings
            ? m_settings->valueOr(QStringLiteral("theme/mode"), QStringLiteral("dark")).toString() == QLatin1String("dark")
            : true;
        const QColor primary = parseColor(
            m_settings ? m_settings->valueOr(QStringLiteral("theme/primaryColor"), QStringLiteral("#3F44BA")).toString() : QStringLiteral("#3F44BA"),
            QColor(QStringLiteral("#3F44BA")));
        const QColor baseSurfaceAlt = colors.dark ? QColor(43, 50, 80) : QColor(246, 248, 253);
        colors.card = colors.dark ? mixColor(QColor(34, 40, 68), primary, 0.10) : QColor(248, 250, 255);
        colors.text = colors.dark ? QColor(244, 247, 255) : QColor(34, 36, 43);
        colors.hover = colors.dark ? mixColor(baseSurfaceAlt, primary.lighter(165), 0.62) : mixColor(baseSurfaceAlt, primary, 0.036);
        colors.outline = colors.dark ? mixColor(QColor(96, 108, 160), primary.lighter(155), 0.72) : QColor(157, 176, 244);
        colors.hairline = colors.dark ? mixColor(QColor(64, 72, 112), primary, 0.12) : mixColor(QColor(212, 222, 252), primary, 0.08);
        return colors;
    }

    QRect screenGeometry(const QPoint &pos) const
    {
        QScreen *screen = QGuiApplication::screenAt(pos);
        if (!screen)
            screen = QGuiApplication::primaryScreen();
        return screen ? screen->geometry() : QRect(0, 0, 800, 600);
    }

    QRect itemRect(int index) const
    {
        const int x = kShadow + kPadding;
        const int y = kShadow + kPadding + index * (kItemHeight + (index == 0 ? kSeparatorHeight : 0));
        return QRect(x, y, kWidth - kPadding * 2, kItemHeight);
    }

    int indexAt(const QPoint &pos) const
    {
        for (int i = 0; i < 2; ++i) {
            if (itemRect(i).contains(pos))
                return i;
        }
        return -1;
    }

    static constexpr int kWidth = 184;
    static constexpr int kHeight = 104;
    static constexpr int kShadow = 18;
    static constexpr int kPadding = 9;
    static constexpr int kItemHeight = 38;
    static constexpr int kSeparatorHeight = 1;
    static constexpr int kRadius = 10;
    static constexpr int kMargin = 6;
    static constexpr int kAnchorXOffset = 8;
    static constexpr int kAnchorYOffset = 8;

    void installGlobalMouseFilter()
    {
        if (m_eventFilterInstalled || !qApp)
            return;
        qApp->installEventFilter(this);
        m_eventFilterInstalled = true;
    }

    RuntimeTray *m_tray = nullptr;
    RuntimeSettings *m_settings = nullptr;
    int m_hoverIndex = -1;
    bool m_eventFilterInstalled = false;
};
#endif

void RuntimeTray::saveMainWindowStateBeforeExit()
{
    if (!m_settings || !m_mainWindow)
        return;
    QWindow *window = m_mainWindow.data();
    const QString visibility = [window]() {
        switch (window->visibility()) {
        case QWindow::Maximized:
            return QStringLiteral("maximized");
        case QWindow::FullScreen:
            return QStringLiteral("fullscreen");
        case QWindow::Minimized:
            return QStringLiteral("minimized");
        default:
            return QStringLiteral("normal");
        }
    }();
    if (visibility == QLatin1String("normal")) {
        const QRect geometry = window->geometry();
        if (geometry.width() >= 320 && geometry.height() >= 240) {
            const double dpr = window && window->screen() ? qMax(1.0, window->screen()->devicePixelRatio()) : 1.0;
            m_settings->setValue(QStringLiteral("windows/main/normalGeometry"), QVariantMap{
                {QStringLiteral("x"), geometry.x()},
                {QStringLiteral("y"), geometry.y()},
                {QStringLiteral("w"), geometry.width()},
                {QStringLiteral("h"), geometry.height()},
                {QStringLiteral("dpr"), dpr},
            });
        }
    }
    m_settings->setValue(QStringLiteral("windows/main/visibility"), visibility);
    m_settings->setValue(QStringLiteral("windows/main/alwaysOnTop"), window->property("alwaysOnTop").toBool());
}

void RuntimeTray::exitApplication()
{
#ifdef Q_OS_WIN
    closeNativeTrayMenu();
#endif
    saveMainWindowStateBeforeExit();
    if (qEnvironmentVariableIsEmpty("QROUNDEDFRAME_DISABLE_RUN_FAST_EXIT")) {
        fflush(stdout);
        fflush(stderr);
#ifdef Q_OS_WIN
        HANDLE process = GetCurrentProcess();
        TerminateProcess(process, 0);
#else
        _Exit(0);
#endif
        return;
    }
    destroyTrayIcon();
    QCoreApplication::quit();
}

RuntimeTray::RuntimeTray(RuntimeSettings *settings, const QString &rootPath, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
{
    m_defaultIconPath = QDir(rootPath).absoluteFilePath(QStringLiteral("resources/app_icon.ico"));
    m_iconPath = settings
        ? settings->valueOr(QStringLiteral("tray/iconPath"), m_defaultIconPath).toString()
        : m_defaultIconPath;
    if (m_iconPath.isEmpty())
        m_iconPath = m_defaultIconPath;
    m_closeToTray = settings
        ? settings->valueOr(QStringLiteral("window/closeToTray"), settings->valueOr(QStringLiteral("window/minimizeToTray"), false)).toBool()
        : false;
    if (m_closeToTray)
        ensureTrayIcon();
}

RuntimeTray::~RuntimeTray()
{
#ifdef Q_OS_WIN
    closeNativeTrayMenu();
#endif
    destroyTrayIcon();
}

void RuntimeTray::registerWindow(QObject *windowObject)
{
    auto *window = qobject_cast<QWindow *>(windowObject);
    if (window)
        m_mainWindow = window;
    if (m_closeToTray)
        ensureTrayIcon();
}

bool RuntimeTray::handleClosing(QObject *windowObject)
{
    if (!qgetenv("CPP_QTQUICK_HOME_FORCE_QUIT").isEmpty())
        return false;
    if (!m_closeToTray)
        return false;
    if (!ensureTrayIcon())
        return false;
    auto *window = qobject_cast<QWindow *>(windowObject);
    if (window)
        m_mainWindow = window;
    if (!m_mainWindow)
        return false;
    m_mainWindow->hide();
    return true;
}

void RuntimeTray::setCloseToTray(bool enabled)
{
    if (m_closeToTray == enabled)
        return;
    m_closeToTray = enabled;
    if (m_settings) {
        m_settings->setValue(QStringLiteral("window/closeToTray"), enabled);
        m_settings->setValue(QStringLiteral("window/minimizeToTray"), enabled);
    }
    if (enabled)
        ensureTrayIcon();
    else
        destroyTrayIcon();
    emit minimizeToTrayChanged(enabled);
}

void RuntimeTray::setIconPath(const QString &path)
{
    const QString next = path.isEmpty() ? m_defaultIconPath : path;
    if (m_iconPath == next)
        return;
    m_iconPath = next;
    if (m_settings)
        m_settings->setValue(QStringLiteral("tray/iconPath"), m_iconPath == m_defaultIconPath ? QString() : m_iconPath);
    updateTrayIcon();
    emit iconPathChanged(m_iconPath);
}

void RuntimeTray::showMainWindow()
{
#ifdef Q_OS_WIN
    closeNativeTrayMenu();
#endif
    if (!m_mainWindow)
        return;
    m_mainWindow->show();
    m_mainWindow->raise();
    m_mainWindow->requestActivate();
}

void RuntimeTray::centerMainWindow()
{
#ifdef Q_OS_WIN
    closeNativeTrayMenu();
#endif
    if (!m_mainWindow)
        return;

    QWindow *window = m_mainWindow.data();
    QScreen *screen = QGuiApplication::screenAt(QCursor::pos());
    if (!screen)
        screen = window->screen();
    if (!screen)
        screen = QGuiApplication::primaryScreen();
    if (!screen) {
        showMainWindow();
        return;
    }

    const QRect available = screen->availableGeometry();
    const QSize size = window->size().isValid() ? window->size() : QSize(936, 749);
    const int x = available.x() + qMax(0, (available.width() - size.width()) / 2);
    const int y = available.y() + qMax(0, (available.height() - size.height()) / 2);

    window->showNormal();
    window->setPosition(x, y);
    window->raise();
    window->requestActivate();
}

QVariantMap RuntimeTray::availableGeometryAt(int x, int y) const
{
    QVariantMap result;
    const QPoint point(x, y);
    QScreen *screen = QGuiApplication::screenAt(point);
    if (!screen)
        screen = QGuiApplication::primaryScreen();
    if (!screen)
        return result;
    const QRect rect = screen->availableGeometry();
    result.insert(QStringLiteral("x"), rect.x());
    result.insert(QStringLiteral("y"), rect.y());
    result.insert(QStringLiteral("w"), rect.width());
    result.insert(QStringLiteral("h"), rect.height());
    return result;
}

void RuntimeTray::raiseTrayMenuWindow(QObject *windowObject)
{
    auto *window = qobject_cast<QWindow *>(windowObject);
    if (!window)
        return;
#ifdef Q_OS_WIN
    HWND hwnd = reinterpret_cast<HWND>(window->winId());
    if (hwnd && IsWindow(hwnd)) {
        DWORD foregroundThread = 0;
        HWND foreground = GetForegroundWindow();
        if (foreground)
            foregroundThread = GetWindowThreadProcessId(foreground, nullptr);
        const DWORD currentThread = GetCurrentThreadId();
        const bool attached = foregroundThread != 0
            && foregroundThread != currentThread
            && AttachThreadInput(currentThread, foregroundThread, TRUE);

        ShowWindow(hwnd, SW_SHOWNOACTIVATE);
        SetWindowPos(
            hwnd,
            HWND_TOPMOST,
            0,
            0,
            0,
            0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOOWNERZORDER | SWP_SHOWWINDOW);
        SetForegroundWindow(hwnd);
        SetActiveWindow(hwnd);
        SetFocus(hwnd);
        if (attached)
            AttachThreadInput(currentThread, foregroundThread, FALSE);
    }
#endif
    window->raise();
    window->requestActivate();
}

bool RuntimeTray::mousePressedOutside(int x, int y, int w, int h) const
{
#ifdef Q_OS_WIN
    if ((GetAsyncKeyState(VK_LBUTTON) & 0x8000) == 0 && (GetAsyncKeyState(VK_RBUTTON) & 0x8000) == 0)
        return false;
#endif
    const QPoint pos = QCursor::pos();
    return !QRect(x, y, qMax(0, w), qMax(0, h)).contains(pos);
}

void RuntimeTray::setTrayMenuVisible(bool visible)
{
    m_trayMenuVisible = visible;
}

bool RuntimeTray::ensureTrayIcon()
{
#ifndef Q_OS_WIN
    if (!QSystemTrayIcon::isSystemTrayAvailable())
        return false;
    if (!m_trayIcon) {
        m_trayIcon = new QSystemTrayIcon(this);
        m_trayPopup = new TrayPopupWidget(this, m_settings);
        if (linuxDesktopNeedsSystemTrayMenu()) {
            m_trayContextMenu = new QMenu();
            QAction *centerAction = m_trayContextMenu->addAction(QStringLiteral("居中主窗口"));
            QAction *exitAction = m_trayContextMenu->addAction(QStringLiteral("退出"));
            connect(centerAction, &QAction::triggered, this, &RuntimeTray::centerMainWindow);
            connect(exitAction, &QAction::triggered, this, &RuntimeTray::exitApplication);
            m_trayIcon->setContextMenu(m_trayContextMenu);
        }
        connect(m_trayIcon, &QSystemTrayIcon::activated, this, [this](QSystemTrayIcon::ActivationReason reason) {
            if (reason == QSystemTrayIcon::Trigger || reason == QSystemTrayIcon::DoubleClick) {
                showMainWindow();
                emit trayPrimaryClicked();
            } else if (reason == QSystemTrayIcon::Context
                       || reason == QSystemTrayIcon::MiddleClick
                       || reason == QSystemTrayIcon::Unknown) {
                if (m_trayContextMenu)
                    return;
                if (m_trayPopup)
                    m_trayPopup->showAt(QCursor::pos());
            }
        });
    }
    updateTrayIcon();
    if (!m_trayIcon->isVisible())
        m_trayIcon->show();
    return true;
#else
    if (!m_trayHwnd) {
        m_trayMessage = WM_APP + 73;
        const wchar_t *className = L"QRoundedFrameTrayWindow";
        WNDCLASSW wc = {};
        wc.lpfnWndProc = &RuntimeTray::trayWndProc;
        wc.hInstance = GetModuleHandleW(nullptr);
        wc.lpszClassName = className;
        RegisterClassW(&wc);
        m_trayHwnd = CreateWindowExW(
            0,
            className,
            L"",
            0,
            0,
            0,
            0,
            0,
            HWND_MESSAGE,
            nullptr,
            GetModuleHandleW(nullptr),
            this);
        if (!m_trayHwnd)
            return false;
        SetWindowLongPtrW(m_trayHwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
    }

    if (!m_trayAdded) {
        NOTIFYICONDATAW nid = {};
        nid.cbSize = sizeof(nid);
        nid.hWnd = m_trayHwnd;
        nid.uID = m_trayId;
        nid.uFlags = NIF_MESSAGE | NIF_TIP;
        nid.uCallbackMessage = m_trayMessage;
        const QString tip = QCoreApplication::applicationName();
        wcsncpy_s(nid.szTip, tip.toStdWString().c_str(), _TRUNCATE);
        if (!Shell_NotifyIconW(NIM_ADD, &nid))
            return false;
        nid.uVersion = NOTIFYICON_VERSION_4;
        Shell_NotifyIconW(NIM_SETVERSION, &nid);
        m_trayAdded = true;
    }
    updateTrayIcon();
    return true;
#endif
}

void RuntimeTray::destroyTrayIcon()
{
#ifdef Q_OS_WIN
    if (m_trayAdded && m_trayHwnd) {
        NOTIFYICONDATAW nid = {};
        nid.cbSize = sizeof(nid);
        nid.hWnd = m_trayHwnd;
        nid.uID = m_trayId;
        Shell_NotifyIconW(NIM_DELETE, &nid);
        m_trayAdded = false;
    }
    if (m_trayIcon) {
        DestroyIcon(m_trayIcon);
        m_trayIcon = nullptr;
    }
    if (m_trayHwnd) {
        DestroyWindow(m_trayHwnd);
        m_trayHwnd = nullptr;
    }
#else
    if (m_trayIcon) {
        m_trayIcon->hide();
        m_trayIcon->setContextMenu(nullptr);
        delete m_trayIcon;
        m_trayIcon = nullptr;
    }
    delete m_trayContextMenu;
    m_trayContextMenu = nullptr;
    delete m_trayPopup;
    m_trayPopup = nullptr;
#endif
}

void RuntimeTray::updateTrayIcon()
{
#ifdef Q_OS_WIN
    if (!m_trayAdded || !m_trayHwnd)
        return;
    HICON icon = reinterpret_cast<HICON>(LoadImageW(
        nullptr,
        reinterpret_cast<LPCWSTR>(QDir::toNativeSeparators(m_iconPath).utf16()),
        IMAGE_ICON,
        GetSystemMetrics(SM_CXSMICON),
        GetSystemMetrics(SM_CYSMICON),
        LR_LOADFROMFILE));
    if (!icon)
        icon = LoadIconW(nullptr, IDI_APPLICATION);

    NOTIFYICONDATAW nid = {};
    nid.cbSize = sizeof(nid);
    nid.hWnd = m_trayHwnd;
    nid.uID = m_trayId;
    nid.uFlags = NIF_ICON | NIF_TIP;
    nid.hIcon = icon;
    const QString tip = QCoreApplication::applicationName();
    wcsncpy_s(nid.szTip, tip.toStdWString().c_str(), _TRUNCATE);
    Shell_NotifyIconW(NIM_MODIFY, &nid);

    if (m_trayIcon && m_trayIcon != icon)
        DestroyIcon(m_trayIcon);
    m_trayIcon = icon;
#else
    if (!m_trayIcon)
        return;
    QIcon icon(m_iconPath);
    if (icon.isNull())
        icon = QGuiApplication::windowIcon();
    if (icon.isNull())
        icon = QIcon::fromTheme(QStringLiteral("applications-system"));
    m_trayIcon->setIcon(icon);
    m_trayIcon->setToolTip(QCoreApplication::applicationName());
#endif
}

#ifdef Q_OS_WIN
LRESULT CALLBACK RuntimeTray::trayWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    auto *self = reinterpret_cast<RuntimeTray *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (self)
        return self->handleTrayMessage(msg, wParam, lParam);
    if (msg == WM_NCCREATE) {
        auto *create = reinterpret_cast<CREATESTRUCTW *>(lParam);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

LRESULT RuntimeTray::handleTrayMessage(UINT msg, WPARAM wParam, LPARAM lParam)
{
    if (msg != m_trayMessage)
        return DefWindowProcW(m_trayHwnd, msg, wParam, lParam);

    const QPoint cursorPos = QCursor::pos();

    const UINT eventFull = UINT(lParam);
    const UINT eventLow = LOWORD(lParam);
    const UINT eventHigh = HIWORD(lParam);
    const bool rightClick = eventFull == WM_RBUTTONUP
        || eventLow == WM_RBUTTONUP
        || eventHigh == WM_RBUTTONUP
        || eventFull == WM_CONTEXTMENU
        || eventLow == WM_CONTEXTMENU
        || eventHigh == WM_CONTEXTMENU;
    const bool leftClick = eventFull == WM_LBUTTONUP
        || eventLow == WM_LBUTTONUP
        || eventHigh == WM_LBUTTONUP
        || eventFull == WM_LBUTTONDBLCLK
        || eventLow == WM_LBUTTONDBLCLK
        || eventHigh == WM_LBUTTONDBLCLK
        || eventFull == NIN_SELECT
        || eventLow == NIN_SELECT
        || eventHigh == NIN_SELECT;

    const DWORD now = GetTickCount();
    if (rightClick) {
        if (now - m_lastTrayContextTick < 250)
            return 0;
        m_lastTrayContextTick = now;
        if (m_trayMenuVisible || m_trayPopupHwnd) {
            closeNativeTrayMenu();
            return 0;
        }
        SetForegroundWindow(m_trayHwnd);
        showNativeTrayMenu(cursorPos);
        PostMessageW(m_trayHwnd, WM_NULL, 0, 0);
        return 0;
    }
    if (leftClick) {
        if (now - m_lastTrayPrimaryTick < 250)
            return 0;
        m_lastTrayPrimaryTick = now;
        showMainWindow();
        emit trayPrimaryClicked();
        return 0;
    }
    return 0;
}

LRESULT CALLBACK RuntimeTray::trayPopupWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    auto *self = reinterpret_cast<RuntimeTray *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (self)
        return self->handleTrayPopupMessage(hwnd, msg, wParam, lParam);
    if (msg == WM_NCCREATE) {
        auto *create = reinterpret_cast<CREATESTRUCTW *>(lParam);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

QRect RuntimeTray::nativeTrayMenuItemRect(int index) const
{
    const int x = kTrayPopupPadding * m_trayPopupScale;
    const int y0 = kTrayPopupPadding * m_trayPopupScale;
    const int itemH = kTrayPopupItemHeight * m_trayPopupScale;
    const int sepH = kTrayPopupSeparatorHeight * m_trayPopupScale;
    const int width = (kTrayPopupWidth - kTrayPopupPadding * 2) * m_trayPopupScale;
    if (index == 0)
        return QRect(x, y0, width, itemH);
    return QRect(x, y0 + itemH + sepH, width, itemH);
}

void RuntimeTray::showNativeTrayMenu(const QPoint &pos)
{
    closeNativeTrayMenu();

    const wchar_t *className = L"QRoundedFrameTrayPopup";
    WNDCLASSW wc = {};
    wc.lpfnWndProc = &RuntimeTray::trayPopupWndProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = className;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    RegisterClassW(&wc);

    POINT cursor = {};
    GetCursorPos(&cursor);
    HMONITOR monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
    UINT dpiX = 96;
    UINT dpiY = 96;
    using GetDpiForMonitorFn = HRESULT(WINAPI *)(HMONITOR, int, UINT *, UINT *);
    auto *shcore = LoadLibraryW(L"Shcore.dll");
    auto getDpiForMonitor = shcore
        ? reinterpret_cast<GetDpiForMonitorFn>(GetProcAddress(shcore, "GetDpiForMonitor"))
        : nullptr;
    if (getDpiForMonitor)
        getDpiForMonitor(monitor, 0, &dpiX, &dpiY);
    else
        dpiX = UINT(GetDpiForWindow(m_trayHwnd));
    if (shcore)
        FreeLibrary(shcore);
    m_trayPopupScale = qMax(1, int(std::lround(double(dpiX) / 96.0)));

    const int width = kTrayPopupWidth * m_trayPopupScale;
    const int height = (kTrayPopupPadding * 2 + kTrayPopupItemHeight * 2 + kTrayPopupSeparatorHeight) * m_trayPopupScale;
    const int margin = 6 * m_trayPopupScale;
    MONITORINFO mi = {};
    mi.cbSize = sizeof(mi);
    if (!GetMonitorInfoW(monitor, &mi)) {
        mi.rcWork.left = 0;
        mi.rcWork.top = 0;
        mi.rcWork.right = GetSystemMetrics(SM_CXSCREEN);
        mi.rcWork.bottom = GetSystemMetrics(SM_CYSCREEN);
    }
    const QRect available(
        mi.rcWork.left,
        mi.rcWork.top,
        mi.rcWork.right - mi.rcWork.left,
        mi.rcWork.bottom - mi.rcWork.top);

    int x = cursor.x - width;
    int y = cursor.y - height;
    if (x < available.x() + margin)
        x = cursor.x;
    if (y < available.y() + margin)
        y = cursor.y;
    x = qBound(available.x() + margin, x, available.x() + available.width() - width - margin);
    y = qBound(available.y() + margin, y, available.y() + available.height() - height - margin);

    m_trayPopupHoverIndex = -1;
    m_trayPopupTrackingMouse = false;
    m_trayPopupHwnd = CreateWindowExW(
        WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
        className,
        L"",
        WS_POPUP,
        x,
        y,
        width,
        height,
        nullptr,
        nullptr,
        GetModuleHandleW(nullptr),
        this);
    if (!m_trayPopupHwnd)
        return;

    SetWindowRgn(m_trayPopupHwnd, CreateRoundRectRgn(0, 0, width + 1, height + 1, kTrayPopupRadius * 2 * m_trayPopupScale, kTrayPopupRadius * 2 * m_trayPopupScale), TRUE);
    ShowWindow(m_trayPopupHwnd, SW_SHOWNOACTIVATE);
    SetWindowPos(m_trayPopupHwnd, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    SetCursor(LoadCursorW(nullptr, IDC_ARROW));
    SetCapture(m_trayPopupHwnd);
    m_trayMenuVisible = true;
}

void RuntimeTray::closeNativeTrayMenu()
{
    m_trayMenuVisible = false;
    m_trayPopupHoverIndex = -1;
    m_trayPopupTrackingMouse = false;
    if (m_trayPopupHwnd) {
        HWND hwnd = m_trayPopupHwnd;
        m_trayPopupHwnd = nullptr;
        if (GetCapture() == hwnd)
            ReleaseCapture();
        if (IsWindow(hwnd))
            DestroyWindow(hwnd);
    }
}

void RuntimeTray::paintNativeTrayMenu(HWND hwnd)
{
    PAINTSTRUCT ps = {};
    HDC hdc = BeginPaint(hwnd, &ps);
    RECT client = {};
    GetClientRect(hwnd, &client);

    const bool dark = m_settings
        ? m_settings->valueOr(QStringLiteral("theme/mode"), QStringLiteral("dark")).toString() == QLatin1String("dark")
        : true;
    const QColor primary = parseColor(
        m_settings ? m_settings->valueOr(QStringLiteral("theme/primaryColor"), QStringLiteral("#3F44BA")).toString() : QStringLiteral("#3F44BA"),
        QColor(QStringLiteral("#3F44BA")));
    const QColor card = dark ? mixColor(QColor(34, 40, 68), primary, 0.10) : QColor(248, 250, 255);
    const QColor baseSurfaceAlt = dark ? QColor(43, 50, 80) : QColor(246, 248, 253);
    const QColor text = dark ? QColor(244, 247, 255) : QColor(34, 36, 43);
    const QColor hover = dark ? mixColor(baseSurfaceAlt, primary.lighter(165), 0.62) : mixColor(baseSurfaceAlt, primary, 0.036);
    const QColor outline = dark ? mixColor(QColor(96, 108, 160), primary.lighter(155), 0.72) : QColor(157, 176, 244);
    const QColor hairline = dark ? mixColor(QColor(64, 72, 112), primary, 0.12) : mixColor(QColor(212, 222, 252), primary, 0.08);

    HBRUSH cardBrush = CreateSolidBrush(colorRef(card));
    FillRect(hdc, &client, cardBrush);
    DeleteObject(cardBrush);

    for (int i = 0; i < 2; ++i) {
        const QRect item = nativeTrayMenuItemRect(i);
        if (m_trayPopupHoverIndex == i) {
            HBRUSH brush = CreateSolidBrush(colorRef(hover));
            HGDIOBJ oldHoverBrush = SelectObject(hdc, brush);
            HGDIOBJ oldHoverPen = SelectObject(hdc, GetStockObject(NULL_PEN));
            RoundRect(
                hdc,
                item.x(),
                item.y(),
                item.x() + item.width(),
                item.y() + item.height(),
                8 * m_trayPopupScale,
                8 * m_trayPopupScale);
            SelectObject(hdc, oldHoverPen);
            SelectObject(hdc, oldHoverBrush);
            DeleteObject(brush);
        }
    }

    const QRect first = nativeTrayMenuItemRect(0);
    RECT sep = {
        first.x(),
        first.y() + first.height(),
        first.x() + first.width(),
        first.y() + first.height() + kTrayPopupSeparatorHeight * m_trayPopupScale
    };
    HBRUSH sepBrush = CreateSolidBrush(colorRef(hairline));
    FillRect(hdc, &sep, sepBrush);
    DeleteObject(sepBrush);

    HPEN pen = CreatePen(PS_SOLID, qMax(1, m_trayPopupScale), colorRef(outline));
    HGDIOBJ oldPen = SelectObject(hdc, pen);
    HGDIOBJ oldBrush = SelectObject(hdc, GetStockObject(NULL_BRUSH));
    RoundRect(hdc, client.left, client.top, client.right - 1, client.bottom - 1, kTrayPopupRadius * 2 * m_trayPopupScale, kTrayPopupRadius * 2 * m_trayPopupScale);
    SelectObject(hdc, oldBrush);
    SelectObject(hdc, oldPen);
    DeleteObject(pen);

    SetBkMode(hdc, TRANSPARENT);
    SetTextColor(hdc, colorRef(text));
    const double fontScale = m_settings ? m_settings->valueOr(QStringLiteral("ui/fontScale"), 1.0).toDouble() : 1.0;
    const UINT windowDpi = qMax<UINT>(96, GetDpiForWindow(hwnd));
    const int fontPixelSize = qMax(12, int(std::lround(13.0 * qBound(0.85, fontScale, 1.35) * double(windowDpi) / 96.0)));
    LOGFONTW lf = {};
    lf.lfHeight = -fontPixelSize;
    lf.lfWeight = FW_NORMAL;
    const QString family = QGuiApplication::font().family();
    wcsncpy_s(lf.lfFaceName, family.toStdWString().c_str(), _TRUNCATE);
    HFONT font = CreateFontIndirectW(&lf);
    HGDIOBJ oldFont = SelectObject(hdc, font);
    const wchar_t *labels[2] = { L"居中主窗口", L"退出" };
    for (int i = 0; i < 2; ++i) {
        const QRect item = nativeTrayMenuItemRect(i);
        RECT textRect = {
            item.x() + 30 * m_trayPopupScale,
            item.y(),
            item.x() + item.width() - 8 * m_trayPopupScale,
            item.y() + item.height()
        };
        DrawTextW(hdc, labels[i], -1, &textRect, DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_END_ELLIPSIS);
    }
    SelectObject(hdc, oldFont);
    DeleteObject(font);

    EndPaint(hwnd, &ps);
}

LRESULT RuntimeTray::handleTrayPopupMessage(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    switch (msg) {
    case WM_NCHITTEST:
        return HTCLIENT;
    case WM_SETCURSOR:
        SetCursor(LoadCursorW(nullptr, IDC_ARROW));
        return TRUE;
    case WM_PAINT:
        paintNativeTrayMenu(hwnd);
        return 0;
    case WM_MOUSEMOVE: {
        SetCursor(LoadCursorW(nullptr, IDC_ARROW));
        if (!m_trayPopupTrackingMouse) {
            TRACKMOUSEEVENT tme = {};
            tme.cbSize = sizeof(tme);
            tme.dwFlags = TME_LEAVE;
            tme.hwndTrack = hwnd;
            if (TrackMouseEvent(&tme))
                m_trayPopupTrackingMouse = true;
        }
        POINT screenPoint = {};
        GetCursorPos(&screenPoint);
        POINT clientPoint = screenPoint;
        ScreenToClient(hwnd, &clientPoint);
        const QPoint p(clientPoint.x, clientPoint.y);
        int nextHover = -1;
        for (int i = 0; i < 2; ++i) {
            if (nativeTrayMenuItemRect(i).contains(p)) {
                nextHover = i;
                break;
            }
        }
        if (m_trayPopupHoverIndex != nextHover) {
            m_trayPopupHoverIndex = nextHover;
            InvalidateRect(hwnd, nullptr, FALSE);
        }
        return 0;
    }
    case WM_MOUSELEAVE:
        m_trayPopupTrackingMouse = false;
        if (m_trayPopupHoverIndex != -1) {
            m_trayPopupHoverIndex = -1;
            InvalidateRect(hwnd, nullptr, FALSE);
        }
        return 0;
    case WM_LBUTTONUP: {
        SetCursor(LoadCursorW(nullptr, IDC_ARROW));
        POINT screenPoint = {};
        GetCursorPos(&screenPoint);
        POINT clientPoint = screenPoint;
        ScreenToClient(hwnd, &clientPoint);
        const QPoint p(clientPoint.x, clientPoint.y);
        int index = -1;
        for (int i = 0; i < 2; ++i) {
            if (nativeTrayMenuItemRect(i).contains(p)) {
                index = i;
                break;
            }
        }
        closeNativeTrayMenu();
        if (index == 0)
            centerMainWindow();
        else if (index == 1)
            exitApplication();
        return 0;
    }
    case WM_RBUTTONDOWN:
    case WM_LBUTTONDOWN: {
        SetCursor(LoadCursorW(nullptr, IDC_ARROW));
        POINT screenPoint = {};
        GetCursorPos(&screenPoint);
        POINT clientPoint = screenPoint;
        ScreenToClient(hwnd, &clientPoint);
        const QPoint p(clientPoint.x, clientPoint.y);
        bool inside = false;
        for (int i = 0; i < 2; ++i) {
            if (nativeTrayMenuItemRect(i).contains(p)) {
                inside = true;
                break;
            }
        }
        if (!inside) {
            closeNativeTrayMenu();
            return 0;
        }
        return 0;
    }
    case WM_RBUTTONUP:
    case WM_CAPTURECHANGED:
    case WM_KILLFOCUS:
    case WM_CANCELMODE:
        closeNativeTrayMenu();
        return 0;
    case WM_NCDESTROY:
        if (m_trayPopupHwnd == hwnd) {
            m_trayPopupHwnd = nullptr;
            m_trayMenuVisible = false;
            m_trayPopupHoverIndex = -1;
            m_trayPopupTrackingMouse = false;
        }
        return DefWindowProcW(hwnd, msg, wParam, lParam);
    default:
        return DefWindowProcW(hwnd, msg, wParam, lParam);
    }
}
#endif

RuntimePerformance::RuntimePerformance(RuntimeSettings *settings, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
{
    const QString saved = settings
        ? settings->valueOr(QStringLiteral("performance/resourceProfile"), QStringLiteral("auto")).toString()
        : QStringLiteral("auto");
    const QVariant legacyLowMemory = settings
        ? settings->value(QStringLiteral("performance/lowMemoryMode"))
        : QVariant();
    if (settings && !settings->value(QStringLiteral("performance/resourceProfile")).isValid() && legacyLowMemory.isValid())
        m_resourceProfile = legacyLowMemory.toBool() ? QStringLiteral("low-memory") : QStringLiteral("normal");
    else
        m_resourceProfile = normalizeProfile(saved);
    m_effectiveProfile = computeEffectiveProfile();
    if (m_settings) {
        const QFileInfo info(m_settings->path());
        m_developerKeyPath = QDir(info.absolutePath()).absoluteFilePath(QStringLiteral("developer.key"));
    }
    m_developerUnlocked = developerKeyPresent();
}

QString RuntimePerformance::normalizeProfile(const QString &profile)
{
    const QString normalized = profile.trimmed().toLower();
    if (normalized == QLatin1String("normal") || normalized == QLatin1String("low-memory") || normalized == QLatin1String("auto"))
        return normalized;
    return QStringLiteral("auto");
}

QString RuntimePerformance::computeEffectiveProfile() const
{
    if (m_resourceProfile != QLatin1String("auto"))
        return m_resourceProfile;
    const int totalMb = totalPhysicalMemoryMb();
    if (totalMb > 0 && totalMb <= 4096)
        return QStringLiteral("low-memory");
    return QStringLiteral("normal");
}

void RuntimePerformance::refreshEffectiveProfile()
{
    const bool wasLow = lowMemoryMode();
    const QString nextEffective = computeEffectiveProfile();
    const bool effectiveChanged = m_effectiveProfile != nextEffective;
    if (effectiveChanged)
        m_effectiveProfile = nextEffective;
    if (effectiveChanged)
        emit effectiveProfileChanged(m_effectiveProfile);
    if (wasLow != lowMemoryMode())
        emit lowMemoryModeChanged(lowMemoryMode());
}

bool RuntimePerformance::developerKeyPresent() const
{
    return !m_developerKeyPath.isEmpty() && QFileInfo::exists(m_developerKeyPath);
}

void RuntimePerformance::setResourceProfile(const QString &profile)
{
    const QString next = normalizeProfile(profile);
    if (m_resourceProfile == next)
        return;
    m_resourceProfile = next;
    if (m_settings)
        m_settings->setValue(QStringLiteral("performance/resourceProfile"), m_resourceProfile);
    emit resourceProfileChanged(m_resourceProfile);
    refreshEffectiveProfile();
}

void RuntimePerformance::setLowMemoryMode(bool enabled)
{
    setResourceProfile(enabled ? QStringLiteral("low-memory") : QStringLiteral("normal"));
}

void RuntimePerformance::lockDeveloperMode()
{
    if (developerKeyPresent())
        return;
    if (!m_developerUnlocked)
        return;
    m_developerUnlocked = false;
    emit developerUnlockedChanged(false);
}

void RuntimePerformance::collectGarbage()
{
    if (QQmlEngine *engine = qmlEngine(this)) {
        engine->trimComponentCache();
        engine->collectGarbage();
    }
}

int RuntimePerformance::totalMemoryMb() const
{
    return totalPhysicalMemoryMb();
}

bool RuntimePerformance::unlockDeveloperMode(const QString &password)
{
    const QByteArray envPassword = qgetenv("FRAMELESS_DEVELOPER_PASSWORD");
    const QString expected = QString::fromLocal8Bit(envPassword);
    const QString configured = m_settings
        ? m_settings->valueOr(QStringLiteral("developer/password"), QStringLiteral("code")).toString()
        : QStringLiteral("code");
    const bool ok = developerKeyPresent() || password == (expected.isEmpty() ? configured : expected);
    if (m_developerUnlocked != ok) {
        m_developerUnlocked = ok;
        emit developerUnlockedChanged(ok);
    }
    return ok;
}

WindowService::WindowService(RuntimeSettings *settings, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
{
    resolveWindowPolicy();
}

void WindowService::resolveWindowPolicy()
{
#ifdef Q_OS_WIN
    const bool forceCustom = envFlag("FRAMELESS_FORCE_CUSTOM_CHROME");
    const bool forceSystem = envFlag("FRAMELESS_FORCE_SYSTEM_CHROME");
    const bool isWin11 = windowsBuildNumber() >= 22000;
    const bool displayFallback = windowsDisplayFallbackNeeded(isWin11);
    const bool customChrome = forceCustom || ((!isWin11 || displayFallback) && !forceSystem);
    if (customChrome) {
        m_shadowPolicy = QStringLiteral("custom-external");
        m_cornerPolicy = QStringLiteral("rounded");
        m_externalShadowSupported = true;
    } else {
        m_shadowPolicy = QStringLiteral("system");
        m_cornerPolicy = QStringLiteral("auto");
        m_externalShadowSupported = false;
    }
    if (envFlag("QROUNDEDFRAME_WINDOW_POLICY_TRACE")) {
        qInfo().noquote() << QStringLiteral("windowPolicy platform=windows build=%1 displayFallback=%2 shadow=%3 corner=%4")
                                  .arg(windowsBuildNumber())
                                  .arg(displayFallback)
                                  .arg(m_shadowPolicy, m_cornerPolicy);
    }
#elif defined(Q_OS_LINUX)
    const bool forceCustom = envFlag("FRAMELESS_FORCE_CUSTOM_CHROME");
    const bool forceSystem = envFlag("FRAMELESS_FORCE_SYSTEM_CHROME");
    const QString session = linuxSessionType();
    const QString desktop = linuxDesktopText();
    const bool allowlisted = session == QLatin1String("x11") && linuxCustomChromeAllowlisted(desktop);
    const bool customChrome = !forceSystem && (forceCustom || allowlisted);
    const bool externalShadow = customChrome && session != QLatin1String("wayland");
    m_shadowPolicy = externalShadow ? QStringLiteral("custom-external") : QStringLiteral("system");
    m_cornerPolicy = customChrome ? QStringLiteral("rounded") : QStringLiteral("auto");
    m_externalShadowSupported = externalShadow;
    if (envFlag("QROUNDEDFRAME_WINDOW_POLICY_TRACE")) {
        qInfo().noquote() << QStringLiteral("windowPolicy platform=linux session=%1 desktop=%2 allowlisted=%3 shadow=%4 corner=%5")
                                  .arg(session, desktop)
                                  .arg(allowlisted)
                                  .arg(m_shadowPolicy, m_cornerPolicy);
    }
#else
    m_shadowPolicy = QStringLiteral("system");
    m_cornerPolicy = QStringLiteral("auto");
    m_externalShadowSupported = false;
#endif
}

QString WindowService::keyForWindow(QObject *windowObject) const
{
    if (!windowObject)
        return QStringLiteral("main");
    const QString key = windowObject->property("windowKey").toString();
    return key.isEmpty() ? QStringLiteral("main") : key;
}

QString WindowService::visibilityName(QWindow *window) const
{
    if (!window)
        return QStringLiteral("normal");
    switch (window->visibility()) {
    case QWindow::Maximized:
        return QStringLiteral("maximized");
    case QWindow::FullScreen:
        return QStringLiteral("fullscreen");
    case QWindow::Minimized:
        return QStringLiteral("minimized");
    default:
        return QStringLiteral("normal");
    }
}

bool WindowService::isChildKey(const QString &key) const
{
    return key.startsWith(QStringLiteral("child-"));
}

void WindowService::handleWindowEvent(const QString &windowKey, const QString &type, const QVariant &payload)
{
    Q_UNUSED(windowKey);
    Q_UNUSED(type);
    Q_UNUSED(payload);
}

bool WindowService::isSnappedState(QObject *windowObject) const
{
    auto *window = qobject_cast<QWindow *>(windowObject);
    if (!window)
        return false;
    const QString visibility = visibilityName(window);
    if (visibility == QLatin1String("maximized") || visibility == QLatin1String("fullscreen"))
        return false;
    QScreen *screen = window->screen() ? window->screen() : QGuiApplication::primaryScreen();
    if (!screen)
        return false;
    const QRect available = screen->availableGeometry();
#ifdef Q_OS_LINUX
    const QRect geometry = managedContentGeometry(windowObject);
#else
    const QRect geometry = window->geometry();
#endif
    const int tolerance = 3;
    const bool fullHeight = qAbs(geometry.top() - available.top()) <= tolerance
        && qAbs(geometry.bottom() - available.bottom()) <= tolerance;
    const bool leftHalf = qAbs(geometry.left() - available.left()) <= tolerance
        && qAbs(geometry.width() - available.width() / 2) <= tolerance;
    const bool rightHalf = qAbs(geometry.right() - available.right()) <= tolerance
        && qAbs(geometry.width() - available.width() / 2) <= tolerance;
    const QVariant explicitValue = window->property("snappedVisual");
    if (explicitValue.isValid() && !explicitValue.toBool())
        return false;
    return fullHeight && (leftHalf || rightHalf);
}

QString WindowService::snapState(QObject *windowObject) const
{
    if (!isSnappedState(windowObject))
        return {};
    auto *window = qobject_cast<QWindow *>(windowObject);
    QScreen *screen = window && window->screen() ? window->screen() : QGuiApplication::primaryScreen();
    if (!window || !screen)
        return QStringLiteral("snapped");
    const QRect available = screen->availableGeometry();
#ifdef Q_OS_LINUX
    const QRect geometry = managedContentGeometry(windowObject);
#else
    const QRect geometry = window->geometry();
#endif
    return geometry.center().x() < available.center().x()
        ? QStringLiteral("left")
        : QStringLiteral("right");
}

QVariantMap WindowService::policySnapshot() const
{
    return {
        {QStringLiteral("shadowPolicy"), m_shadowPolicy},
        {QStringLiteral("cornerPolicy"), m_cornerPolicy},
        {QStringLiteral("externalShadowSupported"), m_externalShadowSupported},
#ifdef Q_OS_WIN
        {QStringLiteral("windowsBuild"), windowsBuildNumber()},
        {QStringLiteral("displayFallback"), windowsDisplayFallbackNeeded(windowsBuildNumber() >= 22000)},
#endif
    };
}

QString WindowService::policySummary() const
{
    const QVariantMap snapshot = policySnapshot();
    return QString::fromUtf8(QJsonDocument::fromVariant(snapshot).toJson(QJsonDocument::Compact));
}

int WindowService::windowStateGeometryInset(QObject *windowObject) const
{
    if (!windowObject)
        return 0;
    bool ok = false;
    const int inset = windowObject->property("windowStateGeometryInset").toInt(&ok);
    return ok ? qBound(0, inset, 128) : 0;
}

QRect WindowService::managedContentGeometry(QObject *windowObject) const
{
    auto *window = qobject_cast<QWindow *>(windowObject);
    if (!window)
        return {};
    QRect geometry = window->geometry();
    const int inset = windowStateGeometryInset(windowObject);
    if (inset > 0 && geometry.width() > inset * 2 && geometry.height() > inset * 2)
        geometry = geometry.adjusted(inset, inset, -inset, -inset);
    return geometry;
}

static QRect outerGeometryForContent(QObject *windowObject, const QRect &contentGeometry)
{
    const int inset = windowObject ? qBound(0, windowObject->property("windowStateGeometryInset").toInt(), 128) : 0;
    return inset > 0
        ? contentGeometry.adjusted(-inset, -inset, inset, inset)
        : contentGeometry;
}

static double windowDevicePixelRatio(QWindow *window)
{
    if (!window)
        return 1.0;
    if (QScreen *screen = window->screen() ? window->screen() : QGuiApplication::primaryScreen())
        return qMax(1.0, screen->devicePixelRatio());
    return 1.0;
}

static QRect scaleSavedContentGeometryForCurrentDpr(const QVariantMap &map, QWindow *window)
{
    QRect geometry(
        map.value(QStringLiteral("x")).toInt(),
        map.value(QStringLiteral("y")).toInt(),
        map.value(QStringLiteral("w")).toInt(),
        map.value(QStringLiteral("h")).toInt());
    const double savedDpr = qMax(1.0, map.value(QStringLiteral("dpr"), 1.0).toDouble());
    const double currentDpr = windowDevicePixelRatio(window);
    if (!qFuzzyCompare(savedDpr, currentDpr)) {
        const double scale = savedDpr / currentDpr;
        geometry.setSize(QSize(qMax(320, int(std::lround(geometry.width() * scale))),
                               qMax(240, int(std::lround(geometry.height() * scale)))));
    }
    return geometry;
}

static QVariantMap contentGeometryMap(const QRect &geometry, QWindow *window)
{
    return {
        {QStringLiteral("x"), geometry.x()},
        {QStringLiteral("y"), geometry.y()},
        {QStringLiteral("w"), geometry.width()},
        {QStringLiteral("h"), geometry.height()},
        {QStringLiteral("dpr"), windowDevicePixelRatio(window)},
    };
}

#ifdef Q_OS_LINUX
static void cancelWindowManagerMoveResize(QWindow *window)
{
#ifdef QROUNDEDFRAME_HAS_X11
    if (!window)
        return;
    Display *display = XOpenDisplay(std::getenv("DISPLAY"));
    if (!display)
        return;
    XEvent event;
    std::memset(&event, 0, sizeof(event));
    event.xclient.type = ClientMessage;
    event.xclient.message_type = XInternAtom(display, "_NET_WM_MOVERESIZE", False);
    event.xclient.display = display;
    event.xclient.window = static_cast<Window>(window->winId());
    event.xclient.format = 32;
    event.xclient.data.l[0] = QCursor::pos().x();
    event.xclient.data.l[1] = QCursor::pos().y();
    event.xclient.data.l[2] = 11; // _NET_WM_MOVERESIZE_CANCEL
    event.xclient.data.l[3] = 0;  // no button for cancel
    event.xclient.data.l[4] = 1;  // normal application source
    XUngrabPointer(display, CurrentTime);
    XSendEvent(display, DefaultRootWindow(display), False, SubstructureRedirectMask | SubstructureNotifyMask, &event);
    XFlush(display);
    XCloseDisplay(display);
#else
    Q_UNUSED(window);
#endif
}
#endif

void WindowService::beginMove(QObject *windowObject, double localX, double localY)
{
    auto *window = qobject_cast<QWindow *>(windowObject);
    if (!window)
        return;
    windowObject->setProperty("_movePressLocalX", localX);
    windowObject->setProperty("_movePressLocalY", localY);
    const bool moveStartedFromSnapped = isSnappedState(windowObject);
    windowObject->setProperty("_moveStartedFromSnapped", moveStartedFromSnapped);
    if (m_settings) {
        const QString key = keyForWindow(windowObject);
        const QVariant savedGeometry = m_settings->value(QStringLiteral("windows/%1/normalGeometry").arg(key));
        if (savedGeometry.isValid())
            windowObject->setProperty("_moveNormalGeometry", savedGeometry);
        else if (!moveStartedFromSnapped) {
            const QRect geometry = managedContentGeometry(windowObject);
            if (geometry.width() >= 320 && geometry.height() >= 240)
                windowObject->setProperty("_moveNormalGeometry", contentGeometryMap(geometry, window));
        }
    }
    window->startSystemMove();
}

void WindowService::updateMove(QObject *windowObject)
{
    Q_UNUSED(windowObject);
}

void WindowService::endMove(QObject *windowObject)
{
    auto *window = qobject_cast<QWindow *>(windowObject);
    if (!window)
        return;
#ifdef Q_OS_LINUX
    QScreen *screen = window->screen() ? window->screen() : QGuiApplication::primaryScreen();
    if (!screen)
        return;
    const QRect available = screen->availableGeometry();
    const QPoint cursor = QCursor::pos();
    const int tolerance = 2;
    const bool moveStartedFromSnapped = windowObject->property("_moveStartedFromSnapped").toBool();
    const auto clearMoveProperties = [&]() {
        windowObject->setProperty("_moveStartedFromSnapped", QVariant());
        windowObject->setProperty("_moveNormalGeometry", QVariant());
        windowObject->setProperty("_movePressLocalX", QVariant());
        windowObject->setProperty("_movePressLocalY", QVariant());
    };
    const auto saveNormalGeometry = [&]() {
        if (!m_settings || moveStartedFromSnapped)
            return;
        const QRect geometry = managedContentGeometry(windowObject);
        if (geometry.width() < 320 || geometry.height() < 240)
            return;
        const QString key = keyForWindow(windowObject);
        m_settings->setValue(QStringLiteral("windows/%1/normalGeometry").arg(key), contentGeometryMap(geometry, window));
    };
    const auto restoreNormalGeometry = [&]() {
        if (!moveStartedFromSnapped)
            return;
        QVariant savedGeometry = windowObject->property("_moveNormalGeometry");
        if (!savedGeometry.isValid() && m_settings) {
            const QString key = keyForWindow(windowObject);
            savedGeometry = m_settings->value(QStringLiteral("windows/%1/normalGeometry").arg(key));
        }
        if (!savedGeometry.canConvert<QVariantMap>())
            return;
        const QVariantMap map = savedGeometry.toMap();
        QRect geometry = scaleSavedContentGeometryForCurrentDpr(map, window);
        if (geometry.width() < 320 || geometry.height() < 240)
            return;
        const int inset = windowStateGeometryInset(windowObject);
        const double localX = windowObject->property("_movePressLocalX").toDouble();
        const double localY = windowObject->property("_movePressLocalY").toDouble();
        const QPoint topLeft = cursor - QPoint(qRound(localX) + inset, qRound(localY) + inset);
        geometry.moveTopLeft(topLeft);
        window->showNormal();
        window->setGeometry(outerGeometryForContent(windowObject, geometry));
    };
    if (qAbs(cursor.y() - available.top()) <= tolerance) {
        cancelWindowManagerMoveResize(window);
        saveNormalGeometry();
        windowObject->setProperty("snappedVisual", false);
        window->showMaximized();
        clearMoveProperties();
        return;
    }
    const bool fullHeight = cursor.y() >= available.top() - tolerance
        && cursor.y() <= available.bottom() + tolerance;
    if (!fullHeight) {
        cancelWindowManagerMoveResize(window);
        restoreNormalGeometry();
        windowObject->setProperty("snappedVisual", false);
        clearMoveProperties();
        return;
    }
    if (qAbs(cursor.x() - available.left()) <= tolerance) {
        cancelWindowManagerMoveResize(window);
        saveNormalGeometry();
        windowObject->setProperty("snappedVisual", true);
        const QRect content(available.left(), available.top(), available.width() / 2, available.height());
        window->showNormal();
        window->setGeometry(outerGeometryForContent(windowObject, content));
        cancelWindowManagerMoveResize(window);
        clearMoveProperties();
        return;
    }
    if (qAbs(cursor.x() - available.right()) <= tolerance) {
        cancelWindowManagerMoveResize(window);
        saveNormalGeometry();
        windowObject->setProperty("snappedVisual", true);
        const int width = available.width() / 2;
        const QRect content(available.right() - width + 1, available.top(), width, available.height());
        window->showNormal();
        window->setGeometry(outerGeometryForContent(windowObject, content));
        cancelWindowManagerMoveResize(window);
        clearMoveProperties();
        return;
    }
    cancelWindowManagerMoveResize(window);
    restoreNormalGeometry();
    windowObject->setProperty("snappedVisual", false);
    clearMoveProperties();
#else
    Q_UNUSED(windowObject)
#endif
}

void WindowService::beginResize(QObject *windowObject, int edges)
{
    auto *window = qobject_cast<QWindow *>(windowObject);
    if (!window)
        return;
    window->startSystemResize(Qt::Edges(edges));
}

void WindowService::updateResize(QObject *windowObject)
{
    Q_UNUSED(windowObject);
}

void WindowService::endResize(QObject *windowObject)
{
    Q_UNUSED(windowObject);
}

void WindowService::restoreNativeManagedWindowState(QObject *windowObject)
{
    if (!m_settings)
        return;
    auto *window = qobject_cast<QWindow *>(windowObject);
    if (!window)
        return;

    const QString key = keyForWindow(windowObject);
    const QVariant savedGeometry = m_settings->value(QStringLiteral("windows/%1/normalGeometry").arg(key));
    if (savedGeometry.canConvert<QVariantMap>()) {
        const QVariantMap map = savedGeometry.toMap();
#ifdef Q_OS_LINUX
        QRect geometry = scaleSavedContentGeometryForCurrentDpr(map, window);
#else
        QRect geometry(
            map.value(QStringLiteral("x")).toInt(),
            map.value(QStringLiteral("y")).toInt(),
            map.value(QStringLiteral("w")).toInt(),
            map.value(QStringLiteral("h")).toInt());
#endif
        if (geometry.width() >= 320 && geometry.height() >= 240) {
            if (QScreen *screen = window->screen() ? window->screen() : QGuiApplication::primaryScreen()) {
                const QRect available = screen->availableGeometry().adjusted(-geometry.width() + 120, -geometry.height() + 80, geometry.width() - 120, geometry.height() - 80);
                if (!available.intersects(geometry))
                    geometry.moveCenter(screen->availableGeometry().center());
            }
#ifdef Q_OS_LINUX
            window->setGeometry(outerGeometryForContent(windowObject, geometry));
#else
            window->setGeometry(geometry);
#endif
        }
    }

    const bool child = isChildKey(key);
    const bool alwaysOnTop = !child && m_settings->valueOr(QStringLiteral("windows/%1/alwaysOnTop").arg(key), false).toBool();
    if (alwaysOnTop)
        setAlwaysOnTop(windowObject, true);

    const QString visibility = m_settings->valueOr(QStringLiteral("windows/%1/visibility").arg(key), QStringLiteral("normal")).toString();
    if (visibility == QLatin1String("maximized")) {
        QTimer::singleShot(0, window, [window]() {
            if (window)
                window->showMaximized();
        });
    } else if (visibility == QLatin1String("fullscreen")) {
        QTimer::singleShot(0, window, [window]() {
            if (window)
                window->showFullScreen();
        });
    }
}

void WindowService::saveWindowState(QObject *windowObject)
{
    if (!m_settings)
        return;
    auto *window = qobject_cast<QWindow *>(windowObject);
    if (!window)
        return;

    const QString key = keyForWindow(windowObject);
    const QString visibility = visibilityName(window);
    if (visibility == QLatin1String("normal")) {
#ifdef Q_OS_LINUX
        QRect geometry = window->geometry();
        const int inset = windowStateGeometryInset(windowObject);
        if (inset > 0 && geometry.width() > inset * 2 && geometry.height() > inset * 2)
            geometry = geometry.adjusted(inset, inset, -inset, -inset);
        if (geometry.width() >= 320 && geometry.height() >= 240) {
            m_settings->setValue(QStringLiteral("windows/%1/normalGeometry").arg(key), contentGeometryMap(geometry, window));
        }
#else
        const QRect geometry = window->geometry();
        if (geometry.width() >= 320 && geometry.height() >= 240) {
            m_settings->setValue(QStringLiteral("windows/%1/normalGeometry").arg(key), QVariantMap{
                {QStringLiteral("x"), geometry.x()},
                {QStringLiteral("y"), geometry.y()},
                {QStringLiteral("w"), geometry.width()},
                {QStringLiteral("h"), geometry.height()},
            });
        }
#endif
    }
    m_settings->setValue(QStringLiteral("windows/%1/visibility").arg(key), visibility);
    if (!isChildKey(key))
        m_settings->setValue(QStringLiteral("windows/%1/alwaysOnTop").arg(key), window->property("alwaysOnTop").toBool());
}

RuntimeDialogs::RuntimeDialogs(const QString &rootPath, QObject *parent)
    : QObject(parent)
    , m_rootPath(rootPath)
{
}

RuntimeSecrets::RuntimeSecrets(const QString &rootPath, QObject *parent)
    : QObject(parent)
{
    const QDir rootDir(rootPath);
    m_secureDir = rootDir.absoluteFilePath(QStringLiteral("user_data/secure"));
    m_vaultFile = QDir(m_secureDir).absoluteFilePath(QStringLiteral("secrets.bin"));
    m_legacyVaultFile = QDir(m_secureDir).absoluteFilePath(QStringLiteral("cpp_secrets.json"));
}

void RuntimeSecrets::load()
{
    if (m_loaded)
        return;
    m_loaded = true;
    m_values = readVault();
}

void RuntimeSecrets::save() const
{
    QDir().mkpath(m_secureDir);
    const QByteArray payload = QJsonDocument(QJsonObject::fromVariantMap(m_values)).toJson(QJsonDocument::Compact);
#if defined(Q_OS_LINUX) && defined(QROUNDEDFRAME_HAS_LIBSECRET)
    if (writeSecretServiceVault(payload))
        return;
    qWarning() << "RuntimeSecrets falling back to local file storage";
#endif
    QSaveFile file(m_vaultFile);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return;
#ifdef Q_OS_WIN
    DATA_BLOB input {};
    input.pbData = reinterpret_cast<BYTE *>(const_cast<char *>(payload.constData()));
    input.cbData = static_cast<DWORD>(payload.size());
    DATA_BLOB output {};
    DATA_BLOB entropy {};
    const QByteArray entropyBytes("QRoundedFrame.RuntimeSecrets.v1");
    entropy.pbData = reinterpret_cast<BYTE *>(const_cast<char *>(entropyBytes.constData()));
    entropy.cbData = static_cast<DWORD>(entropyBytes.size());
    if (!CryptProtectData(&input, L"QRoundedFrame secrets", &entropy, nullptr, nullptr, 0, &output)) {
        qWarning() << "RuntimeSecrets save failed: CryptProtectData" << GetLastError();
        return;
    }
    const QByteArray encrypted(reinterpret_cast<const char *>(output.pbData), int(output.cbData));
    LocalFree(output.pbData);
    file.write(QByteArrayLiteral("QRFS1\n"));
    file.write(encrypted.toBase64());
#else
    file.write(payload);
#endif
    file.commit();
}

QVariantMap RuntimeSecrets::readVault() const
{
    auto parseObject = [](const QByteArray &payload, const QString &source) -> QVariantMap {
        QJsonParseError error {};
        const QJsonDocument doc = QJsonDocument::fromJson(payload, &error);
        if (!doc.isObject()) {
            if (error.error != QJsonParseError::NoError)
                qWarning() << "RuntimeSecrets parse failed" << source << error.errorString();
            return {};
        }
        return doc.object().toVariantMap();
    };

#if defined(Q_OS_LINUX) && defined(QROUNDEDFRAME_HAS_LIBSECRET)
    const QByteArray secretServicePayload = readSecretServiceVault();
    if (!secretServicePayload.isEmpty()) {
        const QVariantMap values = parseObject(secretServicePayload, QStringLiteral("Secret Service"));
        if (!values.isEmpty())
            return values;
    }
#endif

    QFile vault(m_vaultFile);
    if (vault.exists() && vault.open(QIODevice::ReadOnly)) {
        QByteArray payload = vault.readAll();
#ifdef Q_OS_WIN
        if (payload.startsWith("QRFS1\n")) {
            payload = QByteArray::fromBase64(payload.mid(6).trimmed());
            DATA_BLOB input {};
            input.pbData = reinterpret_cast<BYTE *>(payload.data());
            input.cbData = static_cast<DWORD>(payload.size());
            DATA_BLOB output {};
            DATA_BLOB entropy {};
            const QByteArray entropyBytes("QRoundedFrame.RuntimeSecrets.v1");
            entropy.pbData = reinterpret_cast<BYTE *>(const_cast<char *>(entropyBytes.constData()));
            entropy.cbData = static_cast<DWORD>(entropyBytes.size());
            if (CryptUnprotectData(&input, nullptr, &entropy, nullptr, nullptr, 0, &output)) {
                const QByteArray decrypted(reinterpret_cast<const char *>(output.pbData), int(output.cbData));
                LocalFree(output.pbData);
                return parseObject(decrypted, m_vaultFile);
            }
            qWarning() << "RuntimeSecrets load failed: CryptUnprotectData" << GetLastError();
            return {};
        }
#endif
        const QVariantMap values = parseObject(payload, m_vaultFile);
        if (!values.isEmpty())
            return values;
    }

    QFile legacy(m_legacyVaultFile);
    if (legacy.exists() && legacy.open(QIODevice::ReadOnly))
        return parseObject(legacy.readAll(), m_legacyVaultFile);
    return {};
}

void RuntimeSecrets::preload()
{
    load();
}

QVariant RuntimeSecrets::get(const QString &key)
{
    load();
    return m_values.value(key);
}

void RuntimeSecrets::put(const QString &key, const QVariant &value)
{
    load();
    m_values.insert(key, jsonSafeVariantFromAny(value));
    save();
}

void RuntimeSecrets::remove(const QString &key)
{
    load();
    if (!m_values.contains(key))
        return;
    m_values.remove(key);
    save();
}

void RuntimeDialogs::setNativeChildWindowManager(QObject *manager)
{
    m_nativeChildWindowManager = manager;
}

QQmlComponent *RuntimeDialogs::preparedPageComponent(const QString &pageKey)
{
    const QString normalizedKey = pageKey.trimmed().isEmpty() ? QStringLiteral("about") : pageKey.trimmed();
    if (auto *component = m_preparedPageComponents.value(normalizedKey))
        return component;

    auto *engine = qmlEngine(this);
    if (!engine)
        return nullptr;

    const QUrl pageUrl = QUrl::fromLocalFile(absolutePagePathFor(m_rootPath, normalizedKey));
    auto *component = new QQmlComponent(engine, pageUrl, QQmlComponent::PreferSynchronous, this);
    if (component->isError()) {
        qWarning() << "RuntimeDialogs prepareChild failed" << normalizedKey << component->errors();
        delete component;
        return nullptr;
    }
    m_preparedPageComponents.insert(normalizedKey, component);
    return component;
}

void RuntimeDialogs::prepareChild(const QString &pageKey)
{
    preparedPageComponent(pageKey);
}

void RuntimeDialogs::openChild(QObject *parentWindow, const QString &pageKey, const QVariant &properties)
{
    if (!m_nativeChildWindowManager) {
        qWarning() << "RuntimeDialogs missing NativeChildWindowManager";
        return;
    }

    auto *quickParent = qobject_cast<QQuickWindow *>(parentWindow);
    if (!quickParent) {
        qWarning() << "RuntimeDialogs parent is not QQuickWindow" << parentWindow;
        return;
    }

    const QUrl windowSource = QUrl::fromLocalFile(
        QDir(m_rootPath).absoluteFilePath(QStringLiteral("qml/window/NativeChildWindow.qml")));
    const QUrl pageSource = QUrl::fromLocalFile(absolutePagePathFor(m_rootPath, pageKey));
    const QString windowKey = QStringLiteral("child-%1").arg(pageKey);
    const QVariantMap propertyMap = variantMapFromAny(properties);
    preparedPageComponent(pageKey);

    QObject *createdWindow = nullptr;
    const bool ok = QMetaObject::invokeMethod(
        m_nativeChildWindowManager,
        "openChild",
        Q_RETURN_ARG(QObject *, createdWindow),
        Q_ARG(QUrl, windowSource),
        Q_ARG(QUrl, pageSource),
        Q_ARG(QString, pageTitleFor(pageKey)),
        Q_ARG(QString, windowKey),
        Q_ARG(QQuickWindow *, quickParent),
        Q_ARG(QVariantMap, propertyMap));
    if (!ok || !createdWindow)
        qWarning() << "RuntimeDialogs failed to open native child" << pageKey;
}

void RuntimeDialogs::closeChildWindow(QObject *windowObject)
{
    if (!windowObject)
        return;
    const QString windowKey = windowObject->property("windowKey").toString();
    if (m_nativeChildWindowManager && !windowKey.isEmpty()) {
        const bool ok = QMetaObject::invokeMethod(
            m_nativeChildWindowManager,
            "closeChild",
            Q_ARG(QString, windowKey));
        if (ok)
            return;
    }
    windowObject->deleteLater();
}

void RuntimeDialogs::shutdown()
{
    if (!m_nativeChildWindowManager)
        return;
    QMetaObject::invokeMethod(m_nativeChildWindowManager, "closeAll");
}

RuntimeApp::RuntimeApp(QString rootPath, QString dataRootPath, QQmlEngine *engine, CardGlowProvider *cardGlowProvider, QObject *parent)
    : QObject(parent)
    , m_rootPath(std::move(rootPath))
    , m_dataRootPath(std::move(dataRootPath))
    , m_engine(engine)
    , m_cardGlowProvider(cardGlowProvider)
    , m_settings(m_dataRootPath)
    , m_theme(&m_settings)
    , m_performance(&m_settings)
    , m_tray(&m_settings, m_rootPath)
    , m_window(&m_settings)
    , m_dialogs(m_rootPath)
    , m_secrets(m_dataRootPath)
    , m_taskStore(new TaskStore(m_dataRootPath, &m_performance, this))
{
#ifdef Q_OS_WIN
    SYSTEM_INFO systemInfo = {};
    GetSystemInfo(&systemInfo);
    m_cpuProcessorCount = qMax(1, int(systemInfo.dwNumberOfProcessors));
#elif defined(Q_OS_LINUX)
    m_cpuProcessorCount = qMax(1, int(sysconf(_SC_NPROCESSORS_ONLN)));
    m_cpuClockTicks = qMax(1L, sysconf(_SC_CLK_TCK));
#endif
    m_titleBarResourceStatsTimer.setInterval(1500);
    m_titleBarResourceStatsTimer.setTimerType(Qt::VeryCoarseTimer);
    connect(&m_titleBarResourceStatsTimer, &QTimer::timeout, this, &RuntimeApp::refreshTitleBarResourceStats);
    connect(&m_settings, &RuntimeSettings::changed, this, [this](const QString &key, const QVariant &value) {
        Q_UNUSED(value)
        if (key == QLatin1String("ui/showTitleBarResourceStats")
            || key == QLatin1String("ui/showTitleBarCpu")
            || key == QLatin1String("ui/showTitleBarMemory")
            || key == QLatin1String("ui/showTitleBarGpu")) {
            syncTitleBarResourceStatsEnabled();
        }
    });
    syncTitleBarResourceStatsEnabled();

    connect(qApp, &QCoreApplication::aboutToQuit, this, [this]() {
        saveRegisteredMainWindowState();
        closeGpuCounters();
    });
}

QObject *RuntimeApp::taskStore()
{
    return m_taskStore;
}

QString RuntimeApp::envValue(const QString &name) const
{
    return QProcessEnvironment::systemEnvironment().value(name);
}

QString RuntimeApp::pageTitle(const QString &pageKey) const
{
    return pageTitleFor(pageKey);
}

QString RuntimeApp::pageSource(const QString &pageKey) const
{
    return pageSourceFor(pageKey);
}

QString RuntimeApp::pageIcon(const QString &pageKey) const
{
    return pageIconFor(pageKey);
}

QVariantMap RuntimeApp::memorySample(bool includeWorkingSetPrivate) const
{
    QVariantMap sample;
#ifdef Q_OS_WIN
    PROCESS_MEMORY_COUNTERS_EX counters = {};
    counters.cb = sizeof(counters);
    if (GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS *>(&counters), sizeof(counters))) {
        sample.insert(QStringLiteral("rss"), bytesToMb(counters.WorkingSetSize));
        sample.insert(QStringLiteral("private"), bytesToMb(counters.PrivateUsage));
        sample.insert(QStringLiteral("ws_private"), includeWorkingSetPrivate ? currentWorkingSetPrivateMb() : 0.0);
        return sample;
    }
#elif defined(Q_OS_LINUX)
    Q_UNUSED(includeWorkingSetPrivate)
    sample = linuxMemorySampleFromSmapsRollup();
    if (sample.isEmpty())
        sample = linuxMemorySampleFromStatm();
    if (!sample.isEmpty())
        return sample;
#endif
    sample.insert(QStringLiteral("rss"), 0.0);
    sample.insert(QStringLiteral("private"), 0.0);
    sample.insert(QStringLiteral("uss"), 0.0);
    sample.insert(QStringLiteral("pss"), 0.0);
    sample.insert(QStringLiteral("ws_private"), 0.0);
    return sample;
}

bool RuntimeApp::titleBarCpuEnabled() const
{
    const bool legacy = m_settings.valueOr(QStringLiteral("ui/showTitleBarResourceStats"), false).toBool();
    return m_settings.valueOr(QStringLiteral("ui/showTitleBarCpu"), legacy).toBool();
}

bool RuntimeApp::titleBarMemoryEnabled() const
{
    const bool legacy = m_settings.valueOr(QStringLiteral("ui/showTitleBarResourceStats"), false).toBool();
    return m_settings.valueOr(QStringLiteral("ui/showTitleBarMemory"), legacy).toBool();
}

bool RuntimeApp::titleBarGpuEnabled() const
{
    const bool legacy = m_settings.valueOr(QStringLiteral("ui/showTitleBarResourceStats"), false).toBool();
    return m_settings.valueOr(QStringLiteral("ui/showTitleBarGpu"), legacy).toBool();
}

bool RuntimeApp::titleBarResourceStatsEnabledFromSettings() const
{
    return titleBarCpuEnabled() || titleBarMemoryEnabled() || titleBarGpuEnabled();
}

void RuntimeApp::syncTitleBarResourceStatsEnabled()
{
    const bool enabled = titleBarResourceStatsEnabledFromSettings();
    if (m_titleBarResourceStatsEnabled == enabled)
    {
        refreshTitleBarResourceStats();
        return;
    }
    m_titleBarResourceStatsEnabled = enabled;
    emit titleBarResourceStatsEnabledChanged();
    if (enabled) {
        refreshTitleBarResourceStats();
        m_titleBarResourceStatsTimer.start();
    } else {
        m_titleBarResourceStatsTimer.stop();
        closeGpuCounters();
        m_titleBarResourceStats = QVariantMap();
        emit titleBarResourceStatsChanged();
    }
}

void RuntimeApp::refreshTitleBarResourceStats()
{
    if (!m_titleBarResourceStatsEnabled)
        return;
    const bool cpuEnabled = titleBarCpuEnabled();
    const bool memoryEnabled = titleBarMemoryEnabled();
    const bool gpuEnabled = titleBarGpuEnabled();
    if (!cpuEnabled && !memoryEnabled && !gpuEnabled) {
        syncTitleBarResourceStatsEnabled();
        return;
    }
    QVariantMap stats;
    stats.insert(QStringLiteral("cpuEnabled"), cpuEnabled);
    stats.insert(QStringLiteral("memoryEnabled"), memoryEnabled);
    stats.insert(QStringLiteral("gpuEnabled"), gpuEnabled);
    stats.insert(QStringLiteral("cpu"), cpuEnabled ? currentProcessCpuPercent() : -1.0);
    if (memoryEnabled) {
        const QVariantMap memory = memorySample(true);
#ifdef Q_OS_WIN
        stats.insert(QStringLiteral("memory"), memory.value(QStringLiteral("ws_private"), 0.0).toDouble());
#elif defined(Q_OS_LINUX)
        stats.insert(QStringLiteral("memory"), memory.value(QStringLiteral("uss"), memory.value(QStringLiteral("private"), memory.value(QStringLiteral("rss"), 0.0))).toDouble());
#else
        stats.insert(QStringLiteral("memory"), memory.value(QStringLiteral("private"), memory.value(QStringLiteral("rss"), 0.0)).toDouble());
#endif
    } else {
        stats.insert(QStringLiteral("memory"), -1.0);
    }
    stats.insert(QStringLiteral("gpu"), gpuEnabled ? currentProcessGpuPercent() : -1.0);
    if (!gpuEnabled)
        closeGpuCounters();
    if (stats == m_titleBarResourceStats)
        return;
    m_titleBarResourceStats = stats;
    emit titleBarResourceStatsChanged();
}

double RuntimeApp::currentProcessCpuPercent()
{
#ifdef Q_OS_WIN
    FILETIME creation = {};
    FILETIME exit = {};
    FILETIME kernel = {};
    FILETIME user = {};
    FILETIME wall = {};
    GetSystemTimeAsFileTime(&wall);
    if (!GetProcessTimes(GetCurrentProcess(), &creation, &exit, &kernel, &user))
        return -1.0;
    const quint64 processTime = fileTimeToUInt64(kernel) + fileTimeToUInt64(user);
    const quint64 wallTime = fileTimeToUInt64(wall);
    if (m_lastCpuProcessTime100ns == 0 || m_lastCpuWallTime100ns == 0 || wallTime <= m_lastCpuWallTime100ns) {
        m_lastCpuProcessTime100ns = processTime;
        m_lastCpuWallTime100ns = wallTime;
        return 0.0;
    }
    const double processDelta = double(processTime - m_lastCpuProcessTime100ns);
    const double wallDelta = double(wallTime - m_lastCpuWallTime100ns);
    m_lastCpuProcessTime100ns = processTime;
    m_lastCpuWallTime100ns = wallTime;
    return qBound(0.0, processDelta * 100.0 / wallDelta / double(m_cpuProcessorCount), 999.0);
#elif defined(Q_OS_LINUX)
    QFile file(QStringLiteral("/proc/self/stat"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return -1.0;
    const QByteArray line = file.readAll();
    const int closeParen = line.lastIndexOf(')');
    if (closeParen < 0)
        return -1.0;
    const QList<QByteArray> fields = line.mid(closeParen + 2).split(' ');
    if (fields.size() < 15)
        return -1.0;
    const quint64 userTicks = fields.value(11).toULongLong();
    const quint64 kernelTicks = fields.value(12).toULongLong();
    const quint64 processTicks = userTicks + kernelTicks;
    const qint64 wallMs = QDateTime::currentMSecsSinceEpoch();
    if (m_lastCpuWallMs <= 0 || wallMs <= m_lastCpuWallMs) {
        m_lastCpuProcessTicks = processTicks;
        m_lastCpuWallMs = wallMs;
        return 0.0;
    }
    const double processMs = double(processTicks - m_lastCpuProcessTicks) * 1000.0 / double(m_cpuClockTicks);
    const double wallDelta = double(wallMs - m_lastCpuWallMs);
    m_lastCpuProcessTicks = processTicks;
    m_lastCpuWallMs = wallMs;
    return qBound(0.0, processMs * 100.0 / wallDelta / double(m_cpuProcessorCount), 999.0);
#else
    return -1.0;
#endif
}

double RuntimeApp::currentProcessGpuPercent()
{
#ifdef Q_OS_WIN
    if (!m_gpuCountersReady) {
        if (PdhOpenQueryW(nullptr, 0, &m_gpuQuery) != ERROR_SUCCESS)
            return -1.0;
        const PDH_STATUS status = PdhAddEnglishCounterW(
            m_gpuQuery,
            L"\\GPU Engine(*)\\Utilization Percentage",
            0,
            &m_gpuCounter);
        if (status != ERROR_SUCCESS) {
            closeGpuCounters();
            return -1.0;
        }
        PdhCollectQueryData(m_gpuQuery);
        m_gpuCountersReady = true;
        return 0.0;
    }
    if (PdhCollectQueryData(m_gpuQuery) != ERROR_SUCCESS)
        return -1.0;

    DWORD bufferSize = 0;
    DWORD itemCount = 0;
    PDH_STATUS status = PdhGetFormattedCounterArrayW(
        m_gpuCounter,
        PDH_FMT_DOUBLE,
        &bufferSize,
        &itemCount,
        nullptr);
    if (status != PDH_MORE_DATA || bufferSize == 0 || itemCount == 0)
        return -1.0;

    QByteArray buffer(int(bufferSize), Qt::Uninitialized);
    auto *items = reinterpret_cast<PDH_FMT_COUNTERVALUE_ITEM_W *>(buffer.data());
    status = PdhGetFormattedCounterArrayW(
        m_gpuCounter,
        PDH_FMT_DOUBLE,
        &bufferSize,
        &itemCount,
        items);
    if (status != ERROR_SUCCESS)
        return -1.0;

    const QString pidNeedle = QStringLiteral("pid_%1_").arg(GetCurrentProcessId());
    double total = 0.0;
    for (DWORD i = 0; i < itemCount; ++i) {
        if (items[i].FmtValue.CStatus != ERROR_SUCCESS || !items[i].szName)
            continue;
        const QString name = QString::fromWCharArray(items[i].szName);
        if (name.contains(pidNeedle, Qt::CaseInsensitive))
            total += items[i].FmtValue.doubleValue;
    }
    return qBound(0.0, total, 999.0);
#else
    return -1.0;
#endif
}

void RuntimeApp::closeGpuCounters()
{
#ifdef Q_OS_WIN
    if (m_gpuQuery)
        PdhCloseQuery(m_gpuQuery);
    m_gpuQuery = nullptr;
    m_gpuCounter = nullptr;
    m_gpuCountersReady = false;
#endif
}

void RuntimeApp::requestMemorySample(bool includeWorkingSetPrivate)
{
    if (m_memorySamplePending)
        return;
    m_memorySamplePending = true;
    auto *watcher = new QFutureWatcher<QVariantMap>(this);
    m_memorySampleWatcher = watcher;
    connect(watcher, &QFutureWatcher<QVariantMap>::finished, this, [this, watcher]() {
        const QVariantMap sample = watcher->result();
        if (m_memorySampleWatcher == watcher)
            m_memorySampleWatcher.clear();
        m_memorySamplePending = false;
        watcher->deleteLater();
        emit memorySampleReady(sample);
    });
    watcher->setFuture(QtConcurrent::run([includeWorkingSetPrivate]() {
        QVariantMap sample;
#ifdef Q_OS_WIN
        PROCESS_MEMORY_COUNTERS_EX counters = {};
        counters.cb = sizeof(counters);
        if (GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS *>(&counters), sizeof(counters))) {
            sample.insert(QStringLiteral("rss"), bytesToMb(counters.WorkingSetSize));
            sample.insert(QStringLiteral("private"), bytesToMb(counters.PrivateUsage));
            sample.insert(QStringLiteral("ws_private"), includeWorkingSetPrivate ? currentWorkingSetPrivateMb() : 0.0);
            return sample;
        }
#elif defined(Q_OS_LINUX)
        Q_UNUSED(includeWorkingSetPrivate)
        sample = linuxMemorySampleFromSmapsRollup();
        if (sample.isEmpty())
            sample = linuxMemorySampleFromStatm();
        if (!sample.isEmpty())
            return sample;
#else
        Q_UNUSED(includeWorkingSetPrivate)
#endif
        sample.insert(QStringLiteral("rss"), 0.0);
        sample.insert(QStringLiteral("private"), 0.0);
        sample.insert(QStringLiteral("uss"), 0.0);
        sample.insert(QStringLiteral("pss"), 0.0);
        sample.insert(QStringLiteral("ws_private"), 0.0);
        return sample;
    }));
}

void RuntimeApp::logStartupMemorySample(const QString &label) const
{
    const QVariantMap sample = memorySample(true);
    const QString line = QStringLiteral("startup-memory %1 rss=%2MB private=%3MB ws_private=%4MB uss=%5MB pss=%6MB private_dirty=%7MB")
        .arg(label)
        .arg(sample.value(QStringLiteral("rss")).toDouble(), 0, 'f', 1)
        .arg(sample.value(QStringLiteral("private")).toDouble(), 0, 'f', 1)
        .arg(sample.value(QStringLiteral("ws_private")).toDouble(), 0, 'f', 1)
        .arg(sample.value(QStringLiteral("uss")).toDouble(), 0, 'f', 1)
        .arg(sample.value(QStringLiteral("pss")).toDouble(), 0, 'f', 1)
        .arg(sample.value(QStringLiteral("private_dirty")).toDouble(), 0, 'f', 1);
    const QString logPath = QDir(m_dataRootPath).absoluteFilePath(QStringLiteral("user_data/logs/cpp_ui_latest.log"));
    QFile file(logPath);
    if (file.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        QTextStream stream(&file);
        stream << line << '\n';
    }
    qInfo().noquote() << line;
}

QVariantMap RuntimeApp::callWorker(const QString &method, const QVariantMap &payload) const
{
    QVariantMap request;
    request.insert(QStringLiteral("method"), method);
    request.insert(QStringLiteral("payload"), payload);

    QProcess process;
    process.setProgram(QStringLiteral("python"));
    process.setArguments({QStringLiteral("-m"), QStringLiteral("app.workers.business_worker")});
    process.setWorkingDirectory(m_rootPath);
    process.start();
    if (!process.waitForStarted(2500))
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("worker start failed")}};

    const QByteArray line = QJsonDocument(QJsonObject::fromVariantMap(request)).toJson(QJsonDocument::Compact) + '\n';
    process.write(line);
    process.closeWriteChannel();
    if (!process.waitForFinished(8000)) {
        process.kill();
        process.waitForFinished(1000);
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("worker timeout")}};
    }

    const QByteArray output = process.readAllStandardOutput().trimmed();
    const QJsonDocument doc = QJsonDocument::fromJson(output);
    if (!doc.isObject())
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("invalid worker response")}};
    return doc.object().toVariantMap();
}

void RuntimeApp::logRuntime(const QString &message) const
{
    if (qEnvironmentVariableIsSet("QROUNDEDFRAME_VERBOSE_LOG"))
        qInfo().noquote() << QDateTime::currentDateTime().toString(Qt::ISODate) << message;
}

void RuntimeApp::logMemorySample(const QString &label) const
{
    if (qEnvironmentVariableIsSet("QROUNDEDFRAME_VERBOSE_LOG"))
        qInfo().noquote() << "memory-sample" << label;
}

void RuntimeApp::registerMainWindow(QObject *windowObject)
{
    if (!windowObject)
        return;
    if (windowObject->property("windowKey").toString() != QLatin1String("main"))
        return;
    m_mainWindowObject = windowObject;
}

void RuntimeApp::saveRegisteredMainWindowState()
{
    if (m_mainWindowObject)
        m_window.saveWindowState(m_mainWindowObject);
}

void RuntimeApp::beginWindowInteraction()
{
    m_windowInteractionActive = true;
}

void RuntimeApp::endWindowInteraction()
{
    m_windowInteractionActive = false;
}

void RuntimeApp::endWindowInteractionSoon()
{
    QTimer::singleShot(180, this, [this]() {
        m_windowInteractionActive = false;
    });
}

void RuntimeApp::beginVisualTransition()
{
    m_visualTransitionActive = true;
    ++m_aggressiveTrimSerial;
}

void RuntimeApp::endVisualTransitionSoon()
{
    QTimer::singleShot(900, this, [this]() {
        m_visualTransitionActive = false;
    });
}

void RuntimeApp::exitApplication()
{
#ifdef Q_OS_LINUX
    if (qEnvironmentVariableIsEmpty("QROUNDEDFRAME_DISABLE_RUN_FAST_EXIT")) {
        fflush(stdout);
        fflush(stderr);
        _Exit(0);
    }
#endif
    QCoreApplication::quit();
}

void RuntimeApp::trimMemory()
{
    trimMemoryNow();
}

void RuntimeApp::trimMemoryNow()
{
    if (m_windowInteractionActive || m_visualTransitionActive)
        return;
    if (m_cardGlowProvider)
        m_cardGlowProvider->clearCache();
    if (m_engine) {
        m_engine->trimComponentCache();
        m_engine->collectGarbage();
    }
}

void RuntimeApp::trimMemoryAfterPageSettled()
{
    trimMemoryNow();
    scheduleAggressiveTrimAfterPageSettled();
    QTimer::singleShot(900, this, [this]() {
        trimMemoryNow();
        if (!autoMemoryTrimEnabled() || m_windowInteractionActive || m_visualTransitionActive)
            return;
        const QVariantMap sample = memorySample(true);
        const double wsPrivate = sample.value(QStringLiteral("ws_private")).toDouble();
        if (wsPrivate >= pageTrimThresholdMb())
            emptyWorkingSetIfIdle();
    });
}

void RuntimeApp::trimMemoryAfterInlineWindowsClosed()
{
    trimMemoryNow();
}

void RuntimeApp::trimResizeMemory()
{
    trimMemoryNow();
}

bool RuntimeApp::autoMemoryTrimEnabled() const
{
    return m_settings.valueOr(QStringLiteral("performance/autoTrimMemory"), true).toBool();
}

double RuntimeApp::pageTrimThresholdMb() const
{
    const QByteArray aggressivePageTrim = qgetenv("CPP_QTQUICK_HOME_AGGRESSIVE_PAGE_TRIM");
    return aggressivePageTrim.isEmpty()
        ? (m_performance.lowMemoryMode() ? 110.0 : 160.0)
        : qMax(0.0, aggressivePageTrim.toDouble());
}

void RuntimeApp::scheduleAggressiveTrimAfterPageSettled()
{
    if (!autoMemoryTrimEnabled())
        return;
    const quint64 serial = ++m_aggressiveTrimSerial;
    if (m_windowInteractionActive || m_visualTransitionActive || m_aggressiveTrimScheduled)
        return;
    m_aggressiveTrimScheduled = true;
    QTimer::singleShot(1200, this, [this, serial]() {
        m_aggressiveTrimScheduled = false;
        if (serial != m_aggressiveTrimSerial || !autoMemoryTrimEnabled() || m_windowInteractionActive || m_visualTransitionActive)
            return;
        if (m_cardGlowProvider)
            m_cardGlowProvider->clearCache();
        if (m_engine) {
            m_engine->trimComponentCache();
            m_engine->collectGarbage();
            m_engine->clearComponentCache();
        }
    });
}

void RuntimeApp::emptyWorkingSetIfIdle()
{
    if (m_windowInteractionActive || m_visualTransitionActive)
        return;
#ifdef Q_OS_WIN
    EmptyWorkingSet(GetCurrentProcess());
#endif
}

void RuntimeApp::requestOpenChild(const QString &pageKey, const QString &mode, const QVariant &props)
{
    emit openChildRequested(pageKey, mode, props);
}

void RuntimeApp::prepareOpenChild(const QString &pageKey, const QString &mode)
{
    if (mode != QLatin1String("inline"))
        m_dialogs.prepareChild(pageKey);
    emit prepareChildRequested(pageKey, mode);
}
