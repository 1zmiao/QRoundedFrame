# Changelog

## 2026-06-20

### 修复：关闭主窗口时阴影提前消失

**问题**：关闭主窗口时，外置阴影（external shadow）比主窗口先消失。

**原因**：`requestMainClose()` 调用 `App.exitApplication()` 前没有标记窗口关闭。Qt 退出过程中 `onVisibleChanged` 触发 → `syncExternalShadow()` 提前销毁了阴影 HWND。

**修改**：
- `AppWindow.qml`：`requestMainClose()` 设置 `_closingMainWindow = true`；`syncExternalShadow()`、`scheduleNativeShadowShow()`、`markNativeShadowDisplayReady()` 加上关闭守卫

### 修复：关闭主窗口时圆角变直角

**问题**：关闭窗口时 QML 视觉层先被销毁，露出默认直角窗口背景。

**修改**：
- `AppWindow.qml`：关闭时先 `visible = false` 隐藏窗口，再退出进程；`onCornerRadiusChanged` 加上关闭守卫
- `NativeMainContent.qml`：同样的 `NativeHost.visible = false` 预隐藏

### 修复：关闭主窗口后阴影慢半拍

**问题**：之前的修复跳过所有关闭中的阴影操作，导致阴影 HWND 直到进程退出后才被 OS 清理，比窗口消失慢。

**修改**：
- `AppWindow.qml`、`NativeMainContent.qml`：隐藏窗口后、退出前主动调用 `cleanupExternalShadow()` 销毁阴影

### 修复：README 图片路径使用反斜杠导致 GitHub 404

**修改**：三处图片路径 `\` 改为 `/`。
