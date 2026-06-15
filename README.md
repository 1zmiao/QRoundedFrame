# QRoundedFrame

一个面向桌面软件模板的 C++ Qt Quick + QML 圆角窗口框架。

C++ 负责 Qt Quick/QML 启动、窗口壳、主题、设置、托盘、任务列表模型和内存采样；QML 负责界面表现；Python 只作为业务 worker 示例使用。

## 运行

开发期仍然从根目录运行：

```bash
python run.py
```

`run.py` 会启动：

```text
build/cpp_ui/bin/QRoundedFrame.exe
```

如果 exe 不存在，会先调用：

```bat
app\cpp\ui_runtime\build_windows.bat
```

## 打包

Windows 打包：

```bash
python scripts/package_app.py
```

默认输出：

```text
dist/QRoundedFrame/QRoundedFrame.exe
```

## 目录

```text
run.py                         开发期启动入口，负责启动 C++ UI exe
app/cpp_ui_launcher.py         C++ UI 构建/启动辅助
app/cpp/ui_runtime/            C++ Qt Quick UI 主程序
app/cpp/frameless_native/      FramelessNative QML native 插件源码
app/prebuilt/                  已编译 FramelessNative 插件
app/workers/                   Python 业务 worker 示例
app/window_policy.py           平台窗口策略判断
qml/                           QML 界面
resources/                     图标、图片、阴影等资源
scripts/                       项目级检查和打包脚本
third_party/qwindowkit/        vendored QWindowKit
build/                         C++ 中间构建目录
dist/                          打包输出目录
```

## Native 预编译插件

Windows x64 / Qt 6.11 预编译插件位于：

```text
app/prebuilt/win-x64-qt6.11-system/qml/FramelessNative
app/prebuilt/win-x64-qt6.11-custom/qml/FramelessNative
```

- `system`：Windows 11 等可信系统圆角/阴影路径。
- `custom`：Windows 10、虚拟机、Basic Display 等需要自定义圆角和外置阴影的路径。

重新编译：

```bat
app\cpp\frameless_native\build_windows.bat
```

Linux 需要在目标系统重新编译：

```bash
bash app/cpp/frameless_native/build_linux.sh
```

## 架构原则

- QML 只做界面表现，不接管高频窗口行为。
- C++ UI runtime 处理 UI 运行时状态、窗口壳、托盘、模型、内存采样等主进程能力。
- Python 不再常驻 UI 进程；需要业务逻辑时走 `app/workers/`，通过 JSON stdin/stdout、SQLite、文件队列或 IPC 通信。
- 不再保留 `app/native` 这层旧 PySide native runtime，预编译插件统一放在 `app/prebuilt`。

## 检查

```bash
python scripts/check_text_encoding.py
python scripts/check_native_window_integrity.py --require-prebuilt --summary
```

## Linux

Linux 窗口行为、阴影、托盘和内存指标需要在目标桌面环境实测。详见：

```text
LINUX_WINDOW_TESTING.md
```
