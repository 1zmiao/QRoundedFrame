#pragma once

#include <QObject>
#include <QPointer>
#include <QFileSystemWatcher>
#include <QHash>
#include <QUrl>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QString>
#include <QTimer>
#include <QWindow>
#include <QVariant>
#include <QVariantMap>
#include <QFutureWatcher>

class TrayPopupWidget;
class QMenu;
class QSystemTrayIcon;

#ifdef Q_OS_WIN
#include <windows.h>
#include <pdh.h>
#endif

class CardGlowProvider;
class TaskStore;

class RuntimeSettings : public QObject {
    Q_OBJECT
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)
    Q_PROPERTY(QString configDir READ configDir CONSTANT)
public:
    explicit RuntimeSettings(const QString &rootPath, QObject *parent = nullptr);
    int revision() const { return m_revision; }
    QString configDir() const;
    Q_INVOKABLE QVariant valueOr(const QString &key, const QVariant &fallback) const;
    Q_INVOKABLE QVariant value(const QString &key) const;
    Q_INVOKABLE void setValue(const QString &key, const QVariant &value);
    Q_INVOKABLE void remove(const QString &key);
    Q_INVOKABLE QString path() const;
signals:
    void changed(const QString &key, const QVariant &value);
    void revisionChanged();
private:
    void load();
    void save() const;
    void mergeDefaults(const QVariantMap &defaults);
    bool removeNestedValue(const QString &key);
    QString m_filePath;
    QVariantMap m_values;
    int m_revision = 0;
};

class RuntimeTheme : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString mode READ mode NOTIFY modeChanged)
    Q_PROPERTY(QString primaryColor READ primaryColor NOTIFY primaryColorChanged)
    Q_PROPERTY(double fontScale READ fontScale NOTIFY fontScaleChanged)
    Q_PROPERTY(double systemUiScale READ systemUiScale NOTIFY systemUiScaleChanged)
    Q_PROPERTY(bool showColorButton READ showColorButton NOTIFY showColorButtonChanged)
    Q_PROPERTY(double rippleX READ rippleX NOTIFY rippleOriginChanged)
    Q_PROPERTY(double rippleY READ rippleY NOTIFY rippleOriginChanged)
public:
    explicit RuntimeTheme(RuntimeSettings *settings, QObject *parent = nullptr);
    QString mode() const { return m_mode; }
    QString primaryColor() const { return m_mode == QLatin1String("dark") ? m_darkPrimaryColor : m_lightPrimaryColor; }
    double fontScale() const { return m_fontScale; }
    double systemUiScale() const { return m_systemUiScale; }
    bool showColorButton() const { return m_showColorButton; }
    double rippleX() const { return m_rippleX; }
    double rippleY() const { return m_rippleY; }
    Q_INVOKABLE void setMode(const QString &mode);
    Q_INVOKABLE QString toggleMode();
    Q_INVOKABLE void setPrimaryColor(const QString &color);
    Q_INVOKABLE void previewPrimaryColor(const QString &color);
    Q_INVOKABLE QString primaryColorForMode(const QString &mode) const;
    Q_INVOKABLE void setFontScale(double scale);
    Q_INVOKABLE void increaseFontScale();
    Q_INVOKABLE void decreaseFontScale();
    Q_INVOKABLE void resetFontScale();
    Q_INVOKABLE void setShowColorButton(bool enabled);
    Q_INVOKABLE void setRippleOrigin(double x, double y);
    Q_INVOKABLE bool copyText(const QString &text);
    Q_INVOKABLE bool copyToClipboard(const QString &text);
signals:
    void modeChanging(const QString &fromMode, const QString &toMode);
    void modeChanged(const QString &mode);
    void primaryColorChanged(const QString &color);
    void primaryColorCommitted(const QString &color);
    void fontScaleChanged();
    void systemUiScaleChanged();
    void showColorButtonChanged();
    void rippleOriginChanged(double x, double y);
private:
    void installSystemUiScaleWatcher();
    void refreshSystemUiScale();
    void refreshSystemUiScaleWatcherPaths();
    RuntimeSettings *m_settings = nullptr;
    QString m_mode = QStringLiteral("dark");
    QString m_lightPrimaryColor = QStringLiteral("#5886D9");
    QString m_darkPrimaryColor = QStringLiteral("#1D38AC");
    double m_fontScale = 1.0;
    double m_systemUiScale = 1.0;
    bool m_showColorButton = true;
    double m_rippleX = 0.0;
    double m_rippleY = 0.0;
    QFileSystemWatcher m_systemUiScaleWatcher;
    QString m_kdeConfigDir;
    QString m_kdeGlobalsPath;
    QString m_kcmFontsPath;
};

class RuntimePerformance : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool lowMemoryMode READ lowMemoryMode NOTIFY lowMemoryModeChanged)
    Q_PROPERTY(QString effectiveProfile READ effectiveProfile NOTIFY effectiveProfileChanged)
    Q_PROPERTY(QString resourceProfile READ resourceProfile NOTIFY resourceProfileChanged)
    Q_PROPERTY(bool developerKeyPresent READ developerKeyPresent CONSTANT)
    Q_PROPERTY(bool developerUnlocked READ developerUnlocked NOTIFY developerUnlockedChanged)
    Q_PROPERTY(QString developerKeyPath READ developerKeyPath CONSTANT)
public:
    explicit RuntimePerformance(RuntimeSettings *settings, QObject *parent = nullptr);
    bool lowMemoryMode() const { return m_effectiveProfile == QLatin1String("low-memory"); }
    QString effectiveProfile() const { return m_effectiveProfile; }
    QString resourceProfile() const { return m_resourceProfile; }
    bool developerKeyPresent() const;
    bool developerUnlocked() const { return m_developerUnlocked || developerKeyPresent(); }
    QString developerKeyPath() const { return m_developerKeyPath; }
    Q_INVOKABLE void setResourceProfile(const QString &profile);
    Q_INVOKABLE void setLowMemoryMode(bool enabled);
    Q_INVOKABLE bool unlockDeveloperMode(const QString &password);
    Q_INVOKABLE void lockDeveloperMode();
    Q_INVOKABLE void collectGarbage();
    Q_INVOKABLE int totalMemoryMb() const;
signals:
    void lowMemoryModeChanged(bool enabled);
    void resourceProfileChanged(const QString &profile);
    void effectiveProfileChanged(const QString &profile);
    void developerUnlockedChanged(bool enabled);
private:
    static QString normalizeProfile(const QString &profile);
    QString computeEffectiveProfile() const;
    void refreshEffectiveProfile();
    RuntimeSettings *m_settings = nullptr;
    QString m_resourceProfile = QStringLiteral("auto");
    QString m_effectiveProfile = QStringLiteral("normal");
    QString m_developerKeyPath;
    bool m_developerUnlocked = false;
};

class RuntimeTray : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool closeToTray READ closeToTray NOTIFY minimizeToTrayChanged)
    Q_PROPERTY(bool minimizeToTray READ closeToTray NOTIFY minimizeToTrayChanged)
    Q_PROPERTY(QString iconPath READ iconPath NOTIFY iconPathChanged)
public:
    explicit RuntimeTray(RuntimeSettings *settings, const QString &rootPath, QObject *parent = nullptr);
    ~RuntimeTray() override;
    bool closeToTray() const { return m_closeToTray; }
    QString iconPath() const { return m_iconPath; }
    Q_INVOKABLE QString defaultIconPath() const { return m_defaultIconPath; }
    Q_INVOKABLE void registerWindow(QObject *windowObject);
    Q_INVOKABLE bool handleClosing(QObject *windowObject);
    Q_INVOKABLE void setCloseToTray(bool enabled);
    Q_INVOKABLE void setMinimizeToTray(bool enabled) { setCloseToTray(enabled); }
    Q_INVOKABLE void setIconPath(const QString &path);
    Q_INVOKABLE void showMainWindow();
    Q_INVOKABLE void centerMainWindow();
    Q_INVOKABLE void exitApplication();
    Q_INVOKABLE QVariantMap availableGeometryAt(int x, int y) const;
    Q_INVOKABLE void resetMousePressEdge() {}
    Q_INVOKABLE void raiseTrayMenuWindow(QObject *windowObject);
    Q_INVOKABLE bool mousePressedOutside(int x, int y, int w, int h) const;
    Q_INVOKABLE void setTrayMenuVisible(bool visible);
signals:
    void minimizeToTrayChanged(bool enabled);
    void trayContextMenuRequested(int x, int y);
    void trayPrimaryClicked();
    void iconPathChanged(const QString &path);
private:
    void saveMainWindowStateBeforeExit();
    bool ensureTrayIcon();
    void destroyTrayIcon();
    void updateTrayIcon();
#ifdef Q_OS_WIN
    static LRESULT CALLBACK trayWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
    static LRESULT CALLBACK trayPopupWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
    LRESULT handleTrayMessage(UINT msg, WPARAM wParam, LPARAM lParam);
    LRESULT handleTrayPopupMessage(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
    void showNativeTrayMenu(const QPoint &pos);
    void closeNativeTrayMenu();
    void paintNativeTrayMenu(HWND hwnd);
    QRect nativeTrayMenuItemRect(int index) const;
    HWND m_trayHwnd = nullptr;
    HWND m_trayPopupHwnd = nullptr;
    HICON m_trayIcon = nullptr;
    UINT m_trayMessage = 0;
    UINT m_trayId = 1;
    bool m_trayAdded = false;
    bool m_trayPopupTrackingMouse = false;
    int m_trayPopupHoverIndex = -1;
    int m_trayPopupScale = 1;
    DWORD m_lastTrayContextTick = 0;
    DWORD m_lastTrayPrimaryTick = 0;
#else
    QSystemTrayIcon *m_trayIcon = nullptr;
    QMenu *m_trayContextMenu = nullptr;
    TrayPopupWidget *m_trayPopup = nullptr;
#endif
    RuntimeSettings *m_settings = nullptr;
    QPointer<QWindow> m_mainWindow;
    QString m_defaultIconPath;
    QString m_iconPath;
    bool m_closeToTray = false;
    bool m_trayMenuVisible = false;
};

class WindowService : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString windowShadowPolicy READ windowShadowPolicy CONSTANT)
    Q_PROPERTY(QString windowCornerPolicy READ windowCornerPolicy CONSTANT)
    Q_PROPERTY(bool externalShadowSupported READ externalShadowSupported CONSTANT)
public:
    explicit WindowService(RuntimeSettings *settings, QObject *parent = nullptr);
    QString windowShadowPolicy() const { return m_shadowPolicy; }
    QString windowCornerPolicy() const { return m_cornerPolicy; }
    bool externalShadowSupported() const { return m_externalShadowSupported; }
    Q_INVOKABLE void handleWindowEvent(const QString &windowKey, const QString &type, const QVariant &payload);
    Q_INVOKABLE void saveWindowState(QObject *windowObject);
    Q_INVOKABLE void restoreWindowState(QObject *windowObject) { restoreNativeManagedWindowState(windowObject); }
    Q_INVOKABLE void restoreNativeManagedWindowState(QObject *windowObject);
    Q_INVOKABLE void saveNativeManagedWindowState(QObject *windowObject) { saveWindowState(windowObject); }
    Q_INVOKABLE void beginMove(QObject *windowObject, double localX = 0.0, double localY = 0.0);
    Q_INVOKABLE void updateMove(QObject *windowObject);
    Q_INVOKABLE void endMove(QObject *windowObject);
    Q_INVOKABLE void beginResize(QObject *windowObject, int edges);
    Q_INVOKABLE void updateResize(QObject *windowObject);
    Q_INVOKABLE void endResize(QObject *windowObject);
    Q_INVOKABLE bool isSnappedState(QObject *windowObject) const;
    Q_INVOKABLE QString snapState(QObject *windowObject) const;
    Q_INVOKABLE QVariantMap policySnapshot() const;
    Q_INVOKABLE QString policySummary() const;
    Q_INVOKABLE void setAlwaysOnTop(QObject *windowObject, bool enabled)
    {
        auto *window = qobject_cast<QWindow *>(windowObject);
        if (!window)
            return;
#ifdef Q_OS_WIN
        HWND hwnd = reinterpret_cast<HWND>(window->winId());
        if (hwnd && IsWindow(hwnd)) {
            SetWindowPos(
                hwnd,
                enabled ? HWND_TOPMOST : HWND_NOTOPMOST,
                0,
                0,
                0,
                0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOOWNERZORDER | SWP_NOACTIVATE);
            window->setProperty("alwaysOnTop", enabled);
            return;
        }
#endif
        Qt::WindowFlags flags = window->flags();
        if (enabled)
            flags |= Qt::WindowStaysOnTopHint;
        else
            flags &= ~Qt::WindowStaysOnTopHint;
        if (window->flags() == flags)
            return;
        const bool wasVisible = window->isVisible();
        window->setFlags(flags);
        if (wasVisible)
            window->show();
    }
private:
    void resolveWindowPolicy();
    QString keyForWindow(QObject *windowObject) const;
    QString visibilityName(QWindow *window) const;
    bool isChildKey(const QString &key) const;
    int windowStateGeometryInset(QObject *windowObject) const;
    QRect managedContentGeometry(QObject *windowObject) const;
    RuntimeSettings *m_settings = nullptr;
    QString m_shadowPolicy = QStringLiteral("system");
    QString m_cornerPolicy = QStringLiteral("auto");
    bool m_externalShadowSupported = false;
};

class RuntimeDialogs : public QObject {
    Q_OBJECT
public:
    explicit RuntimeDialogs(const QString &rootPath, QObject *parent = nullptr);
    Q_INVOKABLE void prepareChild(const QString &pageKey);
    Q_INVOKABLE void openChild(QObject *parentWindow, const QString &pageKey, const QVariant &properties);
    Q_INVOKABLE void closeChildWindow(QObject *windowObject);
    Q_INVOKABLE void setNativeChildWindowManager(QObject *manager);
    Q_INVOKABLE void shutdown();
private:
    QQmlComponent *preparedPageComponent(const QString &pageKey);
    QString m_rootPath;
    QPointer<QObject> m_nativeChildWindowManager;
    QHash<QString, QQmlComponent *> m_preparedPageComponents;
};

class RuntimeSecrets : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString secureDir READ secureDir CONSTANT)
    Q_PROPERTY(QString vaultFile READ vaultFile CONSTANT)
public:
    explicit RuntimeSecrets(const QString &rootPath, QObject *parent = nullptr);
    QString secureDir() const { return m_secureDir; }
    QString vaultFile() const { return m_vaultFile; }
    Q_INVOKABLE QVariant get(const QString &key);
    Q_INVOKABLE void put(const QString &key, const QVariant &value);
    Q_INVOKABLE void remove(const QString &key);
    Q_INVOKABLE void preload();
    Q_INVOKABLE QString path() const { return m_secureDir; }
private:
    void load();
    void save() const;
    QVariantMap readVault() const;
    QString m_secureDir;
    QString m_vaultFile;
    QString m_legacyVaultFile;
    QVariantMap m_values;
    bool m_loaded = false;
};

class RuntimeApp : public QObject {
    Q_OBJECT
    Q_PROPERTY(QObject *settings READ settings CONSTANT)
    Q_PROPERTY(QObject *theme READ theme CONSTANT)
    Q_PROPERTY(QObject *performance READ performance CONSTANT)
    Q_PROPERTY(QObject *tray READ tray CONSTANT)
    Q_PROPERTY(QObject *window READ window CONSTANT)
    Q_PROPERTY(QObject *dialogs READ dialogs CONSTANT)
    Q_PROPERTY(QObject *secrets READ secrets CONSTANT)
    Q_PROPERTY(QObject *taskStore READ taskStore CONSTANT)
    Q_PROPERTY(bool titleBarResourceStatsEnabled READ titleBarResourceStatsEnabled NOTIFY titleBarResourceStatsEnabledChanged)
    Q_PROPERTY(QVariantMap titleBarResourceStats READ titleBarResourceStats NOTIFY titleBarResourceStatsChanged)
public:
    RuntimeApp(QString rootPath, QString dataRootPath, QQmlEngine *engine, CardGlowProvider *cardGlowProvider, QObject *parent = nullptr);
    QObject *settings() { return &m_settings; }
    QObject *theme() { return &m_theme; }
    QObject *performance() { return &m_performance; }
    QObject *tray() { return &m_tray; }
    QObject *window() { return &m_window; }
    QObject *dialogs() { return &m_dialogs; }
    QObject *secrets() { return &m_secrets; }
    QObject *taskStore();
    bool titleBarResourceStatsEnabled() const { return m_titleBarResourceStatsEnabled; }
    QVariantMap titleBarResourceStats() const { return m_titleBarResourceStats; }
    Q_INVOKABLE QString envValue(const QString &name) const;
    Q_INVOKABLE QString pageTitle(const QString &pageKey) const;
    Q_INVOKABLE QString pageSource(const QString &pageKey) const;
    Q_INVOKABLE QString pageIcon(const QString &pageKey) const;
    Q_INVOKABLE QVariantMap memorySample(bool includeWorkingSetPrivate = true) const;
    Q_INVOKABLE void requestMemorySample(bool includeWorkingSetPrivate = true);
    Q_INVOKABLE void logStartupMemorySample(const QString &label) const;
    Q_INVOKABLE QVariantMap callWorker(const QString &method, const QVariantMap &payload = {}) const;
    Q_INVOKABLE void logRuntime(const QString &message) const;
    Q_INVOKABLE void logMemorySample(const QString &label) const;
    Q_INVOKABLE void registerMainWindow(QObject *windowObject);
    Q_INVOKABLE void saveRegisteredMainWindowState();
    Q_INVOKABLE void beginWindowInteraction();
    Q_INVOKABLE void endWindowInteraction();
    Q_INVOKABLE void endWindowInteractionSoon();
    Q_INVOKABLE void beginVisualTransition();
    Q_INVOKABLE void endVisualTransitionSoon();
    Q_INVOKABLE void exitApplication();
    Q_INVOKABLE void trimMemory();
    Q_INVOKABLE void trimMemoryNow();
    Q_INVOKABLE void trimMemoryAfterPageSettled();
    Q_INVOKABLE void trimMemoryAfterInlineWindowsClosed();
    Q_INVOKABLE void trimResizeMemory();
    Q_INVOKABLE void requestOpenChild(const QString &pageKey, const QString &mode, const QVariant &props);
    Q_INVOKABLE void prepareOpenChild(const QString &pageKey, const QString &mode);
signals:
    void prepareChildRequested(const QString &pageKey, const QString &mode);
    void openChildRequested(const QString &pageKey, const QString &mode, const QVariant &props);
    void memorySampleReady(const QVariantMap &sample);
    void titleBarResourceStatsEnabledChanged();
    void titleBarResourceStatsChanged();
private:
    bool autoMemoryTrimEnabled() const;
    double pageTrimThresholdMb() const;
    void scheduleAggressiveTrimAfterPageSettled();
    void emptyWorkingSetIfIdle();
    bool titleBarResourceStatsEnabledFromSettings() const;
    bool titleBarCpuEnabled() const;
    bool titleBarMemoryEnabled() const;
    bool titleBarGpuEnabled() const;
    void syncTitleBarResourceStatsEnabled();
    void refreshTitleBarResourceStats();
    double currentProcessCpuPercent();
    double currentProcessGpuPercent();
    void closeGpuCounters();
    QString m_rootPath;
    QString m_dataRootPath;
    QPointer<QQmlEngine> m_engine;
    CardGlowProvider *m_cardGlowProvider = nullptr;
    RuntimeSettings m_settings;
    RuntimeTheme m_theme;
    RuntimePerformance m_performance;
    RuntimeTray m_tray;
    WindowService m_window;
    bool m_aggressiveTrimScheduled = false;
    quint64 m_aggressiveTrimSerial = 0;
    bool m_memorySamplePending = false;
    QPointer<QFutureWatcher<QVariantMap>> m_memorySampleWatcher;
    RuntimeDialogs m_dialogs;
    RuntimeSecrets m_secrets;
    TaskStore *m_taskStore = nullptr;
    QPointer<QObject> m_mainWindowObject;
    bool m_windowInteractionActive = false;
    bool m_visualTransitionActive = false;
    bool m_titleBarResourceStatsEnabled = false;
    QVariantMap m_titleBarResourceStats;
    QTimer m_titleBarResourceStatsTimer;
#ifdef Q_OS_WIN
    int m_cpuProcessorCount = 1;
    quint64 m_lastCpuProcessTime100ns = 0;
    quint64 m_lastCpuWallTime100ns = 0;
    bool m_gpuCountersReady = false;
    PDH_HQUERY m_gpuQuery = nullptr;
    PDH_HCOUNTER m_gpuCounter = nullptr;
#elif defined(Q_OS_LINUX)
    long m_cpuClockTicks = 100;
    int m_cpuProcessorCount = 1;
    quint64 m_lastCpuProcessTicks = 0;
    qint64 m_lastCpuWallMs = 0;
#endif
};
