# Native window layer

这个目录是项目的 C++ native 窗口层，供 `qml/window/AppWindow.qml` 使用。

它的职责是处理高频、平台相关、QML/Python 不适合接管的窗口工作：

- QWindowKit native frameless setup
- 标题栏、系统按钮和 hit-test 注册
- Windows snap / resize / maximize / restore 等原生窗口行为
- Win10、虚拟机、Basic Display 等环境下的外置自定义阴影 helper

业务逻辑、配置、托盘、主题状态仍由 Python/QML 负责。

## 构建

Windows 使用项目根目录：

```bat
b.bat
```

会生成两套预编译模块：

```text
app/native/prebuilt/win32-x64-py310-qt6.11-system/qml/FramelessNative
app/native/prebuilt/win32-x64-py310-qt6.11-custom/qml/FramelessNative
```

Linux 暂未提供一键脚本。需要为 Linux 重新编译时，请使用本目录的 CMake 工程，并把生成的 QML 模块放到 `app/native/prebuilt/` 对应平台目录。

`build-*` 目录是编译过程产物，不需要提交到 GitHub。

## QWindowKit

本项目使用 vendored QWindowKit：

https://github.com/stdware/qwindowkit

`third_party/qwindowkit` 当前整包放入仓库，方便 clone 后直接编译。项目中包含针对本模板 resize hit-test 的本地调整，后续升级 QWindowKit 时需要重新核对这些差异。

## 责任边界

- QWindowKit/native 层负责窗口行为。
- `NativeWindowAgent` 是 QML 面向 native 的薄封装。
- `ExternalShadowController` 只负责自定义外置阴影 helper 的创建、穿透、层级和同步，不负责拖拽、贴边、最大化等窗口行为。
- Python 的 `app/window_policy.py` 决定当前平台使用 system/custom 哪条路径；重新编译 C++ 不会改变策略。
