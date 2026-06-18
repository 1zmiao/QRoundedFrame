# C++ UI Runtime

这个目录是当前正式 UI 运行时，负责启动 Qt Quick/QML 主界面，并向 QML 注入 `App` 运行时对象。

## 职责

- 启动 QML、注册 image provider、加载 `FramelessNative` 插件。
- 管理主题、设置、窗口状态、托盘、独立子窗口、任务列表模型、内存采样和 UI 缓存清理。
- 需要 Python 生态时，通过 `app/workers/` 里的 worker 处理业务任务。

真实业务逻辑不要嵌入 C++ UI 进程；需要 Python 时使用 JSON stdin/stdout、SQLite、文件队列或本地 IPC 和 worker 通信。

## 构建

```bat
app\cpp\ui_runtime\build_windows.bat
```

默认 Qt 路径是 `Z:\Qt\6.11.1\msvc2022_64`，可用 `FRAMELESS_QT_PREFIX` 覆盖。

```bash
bash app/cpp/ui_runtime/build_linux.sh
```

Linux 默认从 `qmake6`、`qtpaths6` 或 `/usr` 查找 Qt 6 CMake 包，也可用
`FRAMELESS_QT_PREFIX=/path/to/Qt/6.x/gcc_64` 覆盖。

中间产物：

```text
build\cpp_ui\bin\QRoundedFrame.exe
```

开发运行：

```bat
app\cpp\ui_runtime\run_windows.bat
```

```bash
bash app/cpp/ui_runtime/run_linux.sh
```

项目根目录的 `run.py` 也会启动这个 C++ UI。

## 目录分工

- `app/cpp/ui_runtime/src`：C++ UI 主程序。
- `app/cpp/frameless_native/src`：`FramelessNative` QML native 插件，负责窗口壳、阴影、命中测试等平台能力。
- `app/prebuilt`：只存放 `FramelessNative` 插件产物，不存放 C++ UI exe。
- `build`：所有 C++ 中间构建目录。
- `dist`：打包发布目录。

## Linux

Linux 需要重新编译本目录和 `app/cpp/frameless_native`。C++ UI 入口已经迁移旧版 Linux allocator 设置：

- `mallopt(M_TRIM_THRESHOLD, 128 * 1024)`
- `mallopt(M_MMAP_THRESHOLD, 128 * 1024)`
- `mallopt(M_ARENA_MAX, 2)`，如果平台支持
- 默认 `QT_QUICK_BACKEND=software`，除非环境变量显式覆盖

Linux 的窗口壳、托盘、阴影和内存指标仍需要在目标桌面环境实测。
