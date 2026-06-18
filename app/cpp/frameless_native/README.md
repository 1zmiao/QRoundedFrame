# Native window layer

这个目录是项目的 C++ native 窗口层，供 QML 窗口入口使用。它负责处理高频、平台相关、QML/Python 不适合直接接管的窗口工作：

- QWindowKit native frameless setup
- 标题栏、系统按钮和 hit-test 注册
- Windows snap / resize / maximize / restore 等原生窗口行为
- Win10、虚拟机、Basic Display 等环境下的外置自定义阴影 helper

业务逻辑、配置、托盘、主题状态由 `app/cpp/ui_runtime` 注入给 QML 的运行时对象负责。

## 构建

Windows 使用本目录脚本：

```bat
app\cpp\frameless_native\build_windows.bat
```

会生成两套预编译模块：

```text
app/prebuilt/win-x64-qt6.11-system/qml/FramelessNative
app/prebuilt/win-x64-qt6.11-custom/qml/FramelessNative
```

Linux 使用本目录脚本：

```bash
bash app/cpp/frameless_native/build_linux.sh
```

生成的 QML 模块会放到 `app/prebuilt/` 对应平台目录。

编译中间目录统一放到项目根目录 `build/frameless_native/`，不放在源码目录里。

## QWindowKit

本项目使用 vendored QWindowKit：

https://github.com/stdware/qwindowkit

`third_party/qwindowkit` 当前整包放入仓库，方便 clone 后直接编译。项目不是直接裸用上游窗口，而是在本目录的 native 插件层补了 system/custom 路线、外置阴影、Linux CSD、resize hit-test 和 QML 状态同步。后续升级 QWindowKit 时，必须重新验证这些集成点，不能只替换第三方目录后直接发布。

## 责任边界

- QWindowKit/native 层负责窗口行为。
- `NativeWindowAgent` 是 QML 面向 native 的薄封装。
- `ExternalShadowController` 只负责外置阴影 helper 的创建、穿透、层级和同步，不负责拖拽、贴边、最大化等窗口行为。
- C++ UI runtime 和窗口策略共同决定当前平台使用 system/custom 哪条路径；重新编译 native 插件不会自动改变策略。
