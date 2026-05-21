# Frameless PySide6/QML Template

这是一个可直接运行、可继续复用的 Python + PySide6 + QML 无边框桌面软件模板。它把跨平台窗口壳、标题栏、主题、托盘、配置存储、密文存储、懒加载页面和常用控件拆成独立模块，适合作为后续桌面工具类软件的基础工程。

## 运行

Windows:

```bat
scripts\run_windows.bat
```

Linux:

```bash
bash scripts/run_linux.sh
```

脚本会创建本地 `.venv`，安装 `PySide6` 和 `cryptography`，然后执行 `python run.py`。

## 主要优点

- 原生优先的 Windows 窗口行为：Windows 主窗口使用 `QWidget + QQuickWidget + nativeEvent`，子窗口使用 `QWindow + QAbstractNativeEventFilter`。标题栏拖拽、边缘缩放、最大化拖拽还原、Aero Snap 和 Snap Assist 都尽量交给 Win32 命中测试与系统 caption 行为处理，减少手写几何计算带来的抖动、尺寸递减和贴边状态不一致。
- Linux/QML 路径保持可控：Linux 保留纯 QML `Window` 路径，通过 QML 拖拽、缩放、贴边检测和 `SnapPreviewWindow` 实现接近 Windows 的贴边体验。拖到顶部可预览最大化区域，拖到左右边缘可预览半屏区域，释放后按预览范围放大。
- 无边框体验完整：支持圆角、阴影、最大化、还原、边缘缩放、标题栏拖拽、置顶、托盘关闭、多子窗口、半透明贴边预览、窗口状态保存和恢复。Windows 下最大化、双击标题栏、最大化按钮、顶部贴边、左右贴边后再拖拽标题栏，都会尽量保持原始普通窗口尺寸。
- 实时 UI 缩放：设置页提供字体大小滑杆，同时支持 `Ctrl + 鼠标滚轮` 快速调整界面字号。字号、控件尺寸、标题栏高度、菜单高度和页面间距都通过主题 token 联动，适合不同屏幕尺寸和使用习惯。
- 主题体验更完整：支持亮色/暗色模式、独立主题色、标题栏调色入口和运行时实时预览。切换亮暗主题时使用水波纹涟漪过渡，避免整页硬切换；主题色、字号、圆角、间距都集中在 `qml/core/Theme.qml` 维护。
- 可复用组件体系：标题栏、侧栏、按钮、文本框、复选框、右键菜单、Toast、弹窗、托盘菜单、贴边预览、主题扩散层都在 QML 中独立封装，后续项目可以按模块复制或替换。
- 统一菜单与托盘体验：应用内菜单和托盘菜单使用同一套 QML 视觉语言，支持圆角、自定义多层柔和阴影、再次右键关闭、点击外部关闭和主题色联动。主窗口隐藏到托盘后，托盘右键菜单仍能作为独立顶层 QML 窗口显示。
- 数据存储可选：普通设置写入 `user_data/config/settings.json`；敏感字段可通过 `SecureTextField` 或 `StorageBinding { encrypted: true }` 写入加密文件。页面输入、开关、主题、窗口尺寸和导航宽度都可以复用同一套设置接口。
- 页面创建轻量：`qml/layout/PageHost.qml` 使用 `Loader` 懒加载页面，未访问页面不会提前实例化。适合后续扩展重型工具页、数据面板或插件页面。
- Python/QML 边界清晰：Python 负责配置、加密存储、窗口桥接、托盘、子窗口生命周期和系统能力；QML 负责界面、动效、主题和可复用控件。需要高性能或平台相关逻辑时，可以继续在 Python/C++ 层扩展，再通过桥接接口暴露给 QML。

## 目录结构

```text
app/windows_host.py             Windows 主窗口原生宿主
app/bridge/                     Python <-> QML 桥接层
app/bridge/window_controller.py 子窗口移动、缩放、贴边和状态保存
app/bridge/settings_store.py    普通配置存储
app/bridge/secret_store.py      加密配置存储
app/bridge/theme_controller.py  主题控制
app/bridge/dialog_service.py    子窗口/页面弹出服务
app/bridge/tray_controller.py   托盘服务
qml/NativeMainContent.qml       Windows 主窗口 QML 内容
qml/MainWindow.qml              Linux/QML 主窗口入口
qml/window/                     无边框窗口、标题栏、缩放区、贴边预览
qml/controls/                   可复用控件
qml/layout/                     导航、页面容器、布局组件
qml/pages/                      示例页面
user_data/                      运行时生成的配置和密文数据
```

## 可复用接口

QML 中通过 `App` 访问通用桥接服务：

```qml
// 普通配置
App.settings.valueOr("layout/navWidth", 220)
App.settings.setValue("project/name", "demo")
App.settings.remove("project/name")

// 加密配置
App.secrets.setValue("account/token", token)
App.secrets.value("account/token")
App.secrets.remove("account/token")

// 主题
App.theme.setMode("dark")
App.theme.toggleMode()
App.theme.setPrimaryColor("#537FCD")
App.theme.setFontScale(1.05)
App.theme.setShowColorButton(false)

// 子窗口
App.dialogs.openChild(root.Window.window, "about", ({}))
App.dialogs.closeAll()

// 托盘
App.tray.setMinimizeToTray(true)
App.tray.centerMainWindow()
App.tray.exitApplication()
```

窗口壳内部通过 `App.window` 复用窗口控制能力：

```qml
App.window.restoreWindowState(root)
App.window.saveWindowState(root)
App.window.toggleMaximized(root)
App.window.setAlwaysOnTop(root, true)
App.window.beginMove(root, localX, localY)
App.window.updateMove(root)
App.window.endMove(root)
App.window.beginResize(root, edgeValue)
App.window.updateResize(root)
App.window.endResize(root)
```

Windows 主窗口由 `NativeHost` 暴露宿主接口，供 `qml/NativeMainContent.qml` 使用：

```qml
NativeHost.beginSystemMove(localX, localY)
NativeHost.updateSystemMove()
NativeHost.endSystemMove()
NativeHost.toggleMaximized()
NativeHost.setAlwaysOnTop(true)
NativeHost.showToast("配置更改 - 已保存")
NativeHost.changeThemeWithRipple("light", x, y)
NativeHost.setTitleBarHitTestMetrics(height, leftA, rightA, leftB, rightB)
```

常用 QML 组件可以直接复用：

```qml
AppTextField {
    storageKey: "project/name"
    autoLoad: true
}

SecureTextField {
    storageKey: "account/token"
    autoLoad: true
}

StorageBinding {
    target: notesEditor
    valueProperty: "text"
    storageKey: "private/notes"
    encrypted: true
    autoLoad: true
}
```

## 窗口实现说明

- `qml/window/TitleBar.qml` 会暴露标题栏中真正可拖拽的区域；Windows 下这些区域由原生 `WM_NCHITTEST -> HTCAPTION` 接管，Linux 和兜底路径才使用 QML 鼠标拖拽请求。
- Windows 标题栏拖拽、最大化后拖拽复原、左右贴边和顶部贴边都优先走系统原生 caption 行为，让系统处理 Aero Snap、半透明贴边预览和 Snap Assist。
- `app/windows_host.py` 负责 Windows 主窗口的原生命中测试、最大化还原、普通窗口尺寸记忆和手动兜底；restore-bounds 使用可见窗口尺寸，避免 `AdjustWindowRectEx` 造成复原尺寸递减。
- `app/bridge/window_controller.py` 负责子窗口的原生命中测试、缩放、贴边状态保存、手动兜底和窗口状态保存。
- `qml/window/SnapPreviewWindow.qml` 是 QML/兜底路径的半透明贴边预览层；顶部边缘预览最大化区域，左右边缘预览半屏区域，底部边缘不触发贴边。
- Windows 边缘缩放使用 `WM_NCHITTEST` 返回原生命中区域；Linux 继续保留 QML `ResizeArea` 和平台窗口接口。

## 存储位置

运行时数据写入工程目录下的 `user_data/`：

```text
user_data/
  config/
    settings.json
  secure/
    master.key
    secrets.bin
```

`settings.json` 保存普通配置、主题、窗口尺寸和页面状态。`secrets.bin` 保存加密后的密文内容；默认无密码模式使用本地 `master.key`，后续如需口令模式可在构造 `SecretStore(password="...")` 时扩展。

## 修改入口

- 改 Windows 主窗口行为：`app/windows_host.py`、`qml/NativeMainContent.qml`
- 改 Linux/QML 窗口和子窗口行为：`app/bridge/window_controller.py`、`qml/window/FramelessWindow.qml`
- 改标题栏：`qml/window/TitleBar.qml`
- 改主题 token：`qml/core/Theme.qml`
- 改图标：`qml/core/Icons.qml`
- 改页面：`qml/pages/`
- 改可复用控件：`qml/controls/`
