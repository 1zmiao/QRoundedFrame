#include "card_glow_provider.h"
#include "runtime_app.h"

#include <QApplication>
#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QMetaObject>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QScreen>
#include <QSGRendererInterface>
#include <QSurfaceFormat>
#include <QTextStream>
#include <QTimer>

#ifdef Q_OS_LINUX
#include <malloc.h>
#endif

#ifdef Q_OS_WIN
#include <windows.h>
#include <winternl.h>
#endif

namespace {
QFile *gLogFile = nullptr;

void setDefaultEnv(const char *name, const char *value)
{
    if (qgetenv(name).isEmpty())
        qputenv(name, value);
}

void configureProcessAllocator()
{
#ifdef Q_OS_LINUX
    // 旧 PySide 入口曾在 Python 里调用 mallopt 压低 Linux 常驻内存。
    // 转正后 UI 进程变成 C++，这类设置必须在 C++ 进程启动早期完成，
    // 否则保留 legacy memory_tools.py 也不会影响当前 UI 进程。
    mallopt(M_TRIM_THRESHOLD, 128 * 1024);
    mallopt(M_MMAP_THRESHOLD, 128 * 1024);
#ifdef M_ARENA_MAX
    mallopt(M_ARENA_MAX, 2);
#endif
#endif
}

#ifdef Q_OS_WIN
using RtlGetVersionFunction = LONG(WINAPI *)(PRTL_OSVERSIONINFOW);

bool envFlag(const char *name)
{
    const QByteArray value = qgetenv(name).trimmed().toLower();
    return value == "1" || value == "true" || value == "yes" || value == "on";
}

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

bool windowsDisplayFallbackNeeded()
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
    return textContainsAny(joined, {QStringLiteral("microsoft basic display")});
}
#endif

QString nativeFlavorForHost()
{
#ifdef Q_OS_WIN
    // 当前 QML 壳依赖 FramelessNative 的自定义 hit-test 路线提供稳定边角缩放。
    // win-x64-qt6.11-system 只适合系统边框实验，直接切过去会丢失左右/边角缩放。
    // Win11 原生阴影/圆角仍由 WindowService 策略控制，不等于切换 native import 变体。
    return QStringLiteral("custom");
#elif defined(Q_OS_LINUX)
    return QStringLiteral("custom");
#else
    return QStringLiteral("system");
#endif
}

#ifdef Q_OS_LINUX
QString linuxDesktopTextForRenderBackend()
{
    return QStringList{
        QString::fromLocal8Bit(qgetenv("XDG_CURRENT_DESKTOP")),
        QString::fromLocal8Bit(qgetenv("XDG_SESSION_DESKTOP")),
        QString::fromLocal8Bit(qgetenv("DESKTOP_SESSION")),
    }.join(u';').toLower();
}

bool isKdeOrPlasmaDesktopForRenderBackend()
{
    const QString text = linuxDesktopTextForRenderBackend();
    return text.contains(QStringLiteral("kde")) || text.contains(QStringLiteral("plasma"));
}

qreal readKdeScaleFactorForRenderBackend()
{
    QFile file(QDir::homePath() + QStringLiteral("/.config/kdeglobals"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return 1.0;

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
        const QString key = line.left(equals).trimmed();
        const QString value = line.mid(equals + 1).trimmed();
        if (key == QStringLiteral("ScaleFactor")) {
            bool ok = false;
            const qreal scale = value.toDouble(&ok);
            if (ok && scale > 0.0)
                return scale;
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
        const qreal scale = part.mid(equals + 1).trimmed().toDouble(&ok);
        if (ok && scale > 0.0)
            return scale;
    }
    return 1.0;
}

bool kdeScaledRenderBackendNeeded()
{
    if (!isKdeOrPlasmaDesktopForRenderBackend())
        return false;
    return qAbs(readKdeScaleFactorForRenderBackend() - 1.0) > 0.001;
}
#endif

void configureRenderBackend()
{
#ifdef Q_OS_WIN
    setDefaultEnv("QSG_RHI_BACKEND", "d3d11");
    QQuickWindow::setGraphicsApi(QSGRendererInterface::Direct3D11);
#elif defined(Q_OS_LINUX)
    const QString backend = QString::fromLocal8Bit(qgetenv("QROUNDEDFRAME_RENDER_BACKEND")).trimmed().toLower();
    const bool useOpenGl = backend == QLatin1String("opengl")
        || (backend.isEmpty() && kdeScaledRenderBackendNeeded());
    if (useOpenGl) {
        qputenv("QSG_RHI_BACKEND", "opengl");
        qunsetenv("QT_QUICK_BACKEND");
        QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    } else {
        setDefaultEnv("QT_QUICK_BACKEND", "software");
        QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
    }
#endif
}

void appendLog(const QString &line)
{
    if (!gLogFile || !gLogFile->isOpen())
        return;
    QTextStream stream(gLogFile);
    stream << line << '\n';
    stream.flush();
}

void logScreenSnapshot(const QString &label)
{
    const QList<QScreen *> screens = QGuiApplication::screens();
    appendLog(QStringLiteral("screenSnapshot %1 count=%2 primary=%3 appDpr=%4")
                  .arg(label)
                  .arg(screens.size())
                  .arg(QGuiApplication::primaryScreen() ? QGuiApplication::primaryScreen()->name() : QStringLiteral("<none>"))
                  .arg(QGuiApplication::primaryScreen() ? QGuiApplication::primaryScreen()->devicePixelRatio() : 0.0, 0, 'f', 2));
    for (QScreen *screen : screens) {
        if (!screen)
            continue;
        const QRect geometry = screen->geometry();
        const QRect available = screen->availableGeometry();
        appendLog(QStringLiteral("screen %1 dpr=%2 geometry=%3,%4 %5x%6 available=%7,%8 %9x%10 logicalDpi=%11x%12 physicalDpi=%13x%14")
                      .arg(screen->name())
                      .arg(screen->devicePixelRatio(), 0, 'f', 2)
                      .arg(geometry.x())
                      .arg(geometry.y())
                      .arg(geometry.width())
                      .arg(geometry.height())
                      .arg(available.x())
                      .arg(available.y())
                      .arg(available.width())
                      .arg(available.height())
                      .arg(screen->logicalDotsPerInchX(), 0, 'f', 1)
                      .arg(screen->logicalDotsPerInchY(), 0, 'f', 1)
                      .arg(screen->physicalDotsPerInchX(), 0, 'f', 1)
                      .arg(screen->physicalDotsPerInchY(), 0, 'f', 1));
    }
}

QString findRuntimeRoot(const QString &appDirPath)
{
    const QString envRoot = QString::fromLocal8Bit(qgetenv("QROUNDEDFRAME_ROOT")).trimmed();
    const auto isRuntimeRoot = [](const QDir &dir) {
        if (QFile::exists(dir.absoluteFilePath(QStringLiteral("qml/NativeAppMain.qml")))
            && QFile::exists(dir.absoluteFilePath(QStringLiteral("app/prebuilt")))) {
            return true;
        }
        return false;
    };

    if (!envRoot.isEmpty()) {
        const QDir envDir(QDir::cleanPath(envRoot));
        if (isRuntimeRoot(envDir))
            return envDir.absolutePath();
    }

    QDir dir(QDir::cleanPath(appDirPath));
    for (int i = 0; i < 10; ++i) {
        if (isRuntimeRoot(dir))
            return dir.absolutePath();
        if (!dir.cdUp())
            break;
    }

    return QDir::cleanPath(appDirPath);
}
} // namespace

int main(int argc, char *argv[])
{
    configureProcessAllocator();
    qputenv("QML_DISABLE_DISK_CACHE", "1");
    configureRenderBackend();
#ifdef Q_OS_WIN
    setDefaultEnv("QT_D3D_NO_VBLANK_THREAD", "1");
    setDefaultEnv("QSG_NO_VSYNC", "1");
    setDefaultEnv("QT_QPA_UPDATE_IDLE_TIME", "0");
    setDefaultEnv("QT_QPA_DISABLE_REDIRECTION_SURFACE", "1");
#endif

    QSurfaceFormat format;
    format.setSamples(0);
#if defined(Q_OS_WIN) || defined(Q_OS_LINUX)
    format.setAlphaBufferSize(8);
#endif
    format.setSwapBehavior(QSurfaceFormat::DoubleBuffer);
    QSurfaceFormat::setDefaultFormat(format);
#if defined(Q_OS_WIN) || defined(Q_OS_LINUX)
    QQuickWindow::setDefaultAlphaBuffer(true);
#endif

    QApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("QRoundedFrame"));
    QCoreApplication::setOrganizationDomain(QStringLiteral("qroundedframe.local"));
    QCoreApplication::setApplicationName(QStringLiteral("QRoundedFrame"));
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    const QString root = findRuntimeRoot(QCoreApplication::applicationDirPath());
    const QString envDataRoot = QString::fromLocal8Bit(qgetenv("QROUNDEDFRAME_USER_DATA_ROOT")).trimmed();
    const QString dataRoot = envDataRoot.isEmpty() ? root : QDir::cleanPath(envDataRoot);
    const QString iconPath = QDir(root).absoluteFilePath(QStringLiteral("resources/app_icon.ico"));
    if (QFile::exists(iconPath))
        QGuiApplication::setWindowIcon(QIcon(iconPath));

    QDir(dataRoot).mkpath(QStringLiteral("user_data/logs"));
    QFile logFile(QDir(dataRoot).absoluteFilePath(QStringLiteral("user_data/logs/cpp_ui_latest.log")));
    if (logFile.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        gLogFile = &logFile;
    logScreenSnapshot(QStringLiteral("startup"));

    const QString qmlDir = QDir(root).absoluteFilePath(QStringLiteral("qml"));
    const QString nativeFlavor = nativeFlavorForHost();
#ifdef Q_OS_WIN
    const QString nativeTag = QStringLiteral("win-x64-qt6.11-%1").arg(nativeFlavor);
#elif defined(Q_OS_LINUX)
    const QString nativeTag = QStringLiteral("linux-x64-qt6.11-%1").arg(nativeFlavor);
#else
    const QString nativeTag = QStringLiteral("win-x64-qt6.11-%1").arg(nativeFlavor);
#endif
    const QString nativeImportDir = QDir(root).absoluteFilePath(
        QStringLiteral("app/prebuilt/%1/qml").arg(nativeTag));
    const QString nativePluginDir = QDir(nativeImportDir).absoluteFilePath(QStringLiteral("FramelessNative"));
#ifdef Q_OS_WIN
    SetDllDirectoryW(reinterpret_cast<LPCWSTR>(nativePluginDir.utf16()));
    qputenv("PATH", QDir::toNativeSeparators(nativePluginDir).toLocal8Bit() + ";" + qgetenv("PATH"));
#endif

    appendLog(QStringLiteral("root=%1").arg(root));
    appendLog(QStringLiteral("dataRoot=%1").arg(dataRoot));
    appendLog(QStringLiteral("qmlDir=%1").arg(qmlDir));
    appendLog(QStringLiteral("nativeImportDir=%1").arg(nativeImportDir));
    appendLog(QStringLiteral("nativePluginDir=%1").arg(nativePluginDir));
    appendLog(QStringLiteral("nativeFlavor=%1 nativeTag=%2").arg(nativeFlavor, nativeTag));
    appendLog(QStringLiteral("host=QQuickWindow+NativeAppMain"));
    appendLog(QStringLiteral("renderBackend request=%1 QSG_RHI_BACKEND=%2 QT_QUICK_BACKEND=%3")
                  .arg(QString::fromLocal8Bit(qgetenv("QROUNDEDFRAME_RENDER_BACKEND")))
                  .arg(QString::fromLocal8Bit(qgetenv("QSG_RHI_BACKEND")))
                  .arg(QString::fromLocal8Bit(qgetenv("QT_QUICK_BACKEND"))));

    QQmlApplicationEngine engine;
    engine.addImportPath(qmlDir);
    engine.addImportPath(nativeImportDir);
    auto *cardGlowProvider = new CardGlowProvider();
    engine.addImageProvider(QStringLiteral("cardaccent"), cardGlowProvider);

    RuntimeApp appBridge(root, dataRoot, &engine, cardGlowProvider);
    engine.rootContext()->setContextProperty(QStringLiteral("App"), &appBridge);
    QString policySummary;
    QMetaObject::invokeMethod(appBridge.window(), "policySummary", Q_RETURN_ARG(QString, policySummary));
    appendLog(QStringLiteral("windowPolicy=%1").arg(policySummary));
    QObject::connect(&engine, &QQmlApplicationEngine::warnings, &app, [](const QList<QQmlError> &warnings) {
        for (const QQmlError &warning : warnings) {
            qWarning().noquote() << warning.toString();
            appendLog(warning.toString());
        }
    });
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, []() {
        appendLog(QStringLiteral("objectCreationFailed"));
        QCoreApplication::exit(1);
    }, Qt::QueuedConnection);

    const QUrl mainUrl = QUrl::fromLocalFile(QDir(qmlDir).absoluteFilePath(QStringLiteral("NativeAppMain.qml")));
    engine.load(mainUrl);
    if (engine.rootObjects().isEmpty()) {
        appendLog(QStringLiteral("rootObjects empty: %1").arg(mainUrl.toString()));
        return 1;
    }
    appBridge.registerMainWindow(engine.rootObjects().first());

    if (qEnvironmentVariableIsSet("QROUNDEDFRAME_STARTUP_MEMORY_LOG")) {
        QTimer::singleShot(2000, &appBridge, [&appBridge]() { appBridge.logStartupMemorySample(QStringLiteral("2s")); });
        QTimer::singleShot(7000, &appBridge, [&appBridge]() { appBridge.logStartupMemorySample(QStringLiteral("7s")); });
        QTimer::singleShot(15000, &appBridge, [&appBridge]() { appBridge.logStartupMemorySample(QStringLiteral("15s")); });
    }

    bool ok = false;
    const int closeMs = qEnvironmentVariableIntValue("CPP_QTQUICK_HOME_CLOSE_MS", &ok);
    if (ok && closeMs > 0) {
        QTimer::singleShot(closeMs, &appBridge, [&appBridge]() {
            appBridge.saveRegisteredMainWindowState();
            qputenv("CPP_QTQUICK_HOME_FORCE_QUIT", "1");
            QCoreApplication::quit();
        });
    }

    const QByteArray pageSequence = qgetenv("CPP_QTQUICK_HOME_PAGE_SEQUENCE");
    if (!pageSequence.isEmpty()) {
        const QList<QByteArray> pages = pageSequence.split(',');
        int delay = 1200;
        for (const QByteArray &page : pages) {
            const QString pageKey = QString::fromUtf8(page).trimmed();
            if (pageKey.isEmpty())
                continue;
            QTimer::singleShot(delay, &app, [pageKey, &engine]() {
                if (engine.rootObjects().isEmpty())
                    return;
                QMetaObject::invokeMethod(
                    engine.rootObjects().first(),
                    "smokeShowPage",
                    Q_ARG(QVariant, pageKey));
            });
            delay += 1200;
        }
    }

    const QByteArray childPage = qgetenv("CPP_QTQUICK_HOME_OPEN_CHILD");
    if (!childPage.isEmpty()) {
        QTimer::singleShot(1600, &appBridge, [childPage, &appBridge, &engine]() {
            QObject *window = engine.rootObjects().isEmpty() ? nullptr : engine.rootObjects().first();
            QMetaObject::invokeMethod(
                appBridge.dialogs(),
                "openChild",
                Q_ARG(QObject *, window),
                Q_ARG(QString, QString::fromUtf8(childPage).trimmed()),
                Q_ARG(QVariant, QVariantMap{}));
        });
    }
    return app.exec();
}
