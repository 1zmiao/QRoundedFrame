# Frameless PySide6/QML Template

A runnable Python + PySide6 + QML desktop-shell template for reusable frameless windows, lazy pages, theme switching, normal settings, encrypted settings, tray integration, and themed reusable controls.

## Run

Linux:

```bash
cd frameless_pyside6_template
bash scripts/run_linux.sh
```

Windows:

```bat
scripts\run_windows.bat
```

The scripts create a local `.venv`, install `PySide6` and `cryptography`, then run `python run.py`.

## Included structure

```text
app/bridge/                 Python <-> QML bridge
qml/window/FramelessWindow.qml
qml/window/TitleBar.qml
qml/window/ResizeArea.qml
qml/window/SnapPreviewWindow.qml
qml/window/ThemeTransitionLayer.qml
qml/controls/               Reusable buttons, fields, dialogs, menus
qml/core/Theme.qml          Theme tokens
qml/core/Icons.qml          Centralized icon drawing registry
qml/layout/PageHost.qml     Lazy page loader
qml/layout/ResizableSideNav.qml
qml/pages/                  Demo pages
user_data/                  Generated at runtime
```

## Important implementation notes

- `FramelessWindow.qml` is the base shell for main and child windows.
- Title-bar drag is armed on press but does not start until the pointer moves past a threshold. This prevents a maximized window from restoring on a simple click.
- Drag sessions are polled every 8 ms in `WindowController` so snap preview and release detection remain stable at screen edges.
- Top screen-edge drag previews maximize the window; left and right previews snap to half screen. Bottom-edge snap is disabled.
- Windows uses the native DWM frame only for drop shadow and system behavior; the visible rounded surface is rendered by antialiased QML rectangles instead of a jagged QRegion mask. Linux keeps the transparent QML shell and uses compositor behavior where available.
- Theme ripple animation uses five delayed annular soft waves. The ripple layer is transparent in the center and low-opacity at the edge, so it is visible over panels without turning labels or controls into a solid-color overlay.
- Pages are loaded through `PageHost.qml` with `Loader`, so non-current pages are not created.
- Icons for title bar, navigation, fields, dialogs, and tray menu are centralized in `qml/core/Icons.qml`.
- `AppTextField` uses a custom themed context menu. Encrypted fields use the same input component with `encrypted: true` and a lock/unlock toggle.
- Tray right-click uses a QML `TrayMenuWindow` so the menu follows the same theme instead of the native menu style.

## Storage

Demo data is written under the software root, not the OS config directory:

```text
frameless_pyside6_template/
└─ user_data/
   ├─ config/
   │  └─ settings.json
   └─ secure/
      ├─ master.key
      └─ secrets.bin
```

`secrets.bin` has a short readable filename; the file content is encrypted gibberish. Passwordless mode stores a local `master.key`; password mode can be added by constructing `SecretStore(password="...")`.

## Storage examples

Normal field:

```qml
AppTextField {
    id: projectName
    storageKey: "project/name"
    autoLoad: true
}
```

Encrypted field:

```qml
SecureTextField {
    id: tokenField
    storageKey: "account/token"
    autoLoad: true
}
```

Decorator style for a future multiline editor:

```qml
TextEdit { id: notesEditor }

StorageBinding {
    target: notesEditor
    valueProperty: "text"
    storageKey: "private/notes"
    encrypted: true
    autoLoad: true
}
```

## v10 focus

- 修复 Windows 原生事件过滤器里 `msg.hwnd` 偶发为空导致的文本框点击报错。
- 主题切换只保留主窗口底层的一处五层圆形涟漪扩散，取消卡片/侧栏自己的多点扩散，避免视觉上像多个异常涟漪点。
- 左右贴边吸附后，再拖动标题栏会恢复到吸附前的原窗口大小。
- 标题栏调色按钮右键“隐藏调色按钮”改为走 `ThemeController.setShowColorButton()`，设置页勾选项也走同一接口，状态可正确同步。
- 月亮图标改成空心月牙；置顶启用时只填充图标本身，按钮背景不再整块填色。
- 窗口圆角比 v9 再小 2px；Windows 下把可见 QML 窗口面板轻微内缩 1px，让系统阴影不要完全贴齐可见圆角边界，降低阴影直角感。
- 界面可见文案改为中文，保留代码路径、类名和文件名等技术标识。

## v27 Windows 原生窗口壳说明

本版本在 Windows 上新增 `app/windows_host.py`：

- Windows 主窗口改为 `QWidget + nativeEvent + QQuickWidget`。
- QML 页面、主题、菜单、托盘、配置、密文存储等功能继续复用原组件。
- Windows 拖拽移动通过 `WM_NCLBUTTONDOWN / HTCAPTION` 交给系统处理。
- 窗口四边/四角缩放通过 `WM_NCHITTEST` 返回原生命中区域处理。
- Linux 仍加载 `qml/MainWindow.qml`，保持原来的 `QML Window + startSystemMove/startSystemResize` 逻辑。

如果要修改 Windows 主窗口行为，优先修改：

```text
app/windows_host.py
qml/NativeMainContent.qml
```

如果要修改界面、页面、主题、按钮、菜单，仍然修改：

```text
qml/core/
qml/controls/
qml/layout/
qml/pages/
qml/window/TitleBar.qml
```
