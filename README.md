# Python PySide6 Frameless

一个面向真实桌面环境的 PySide6 + QML 无边框窗口模板。它不是只在 Windows 11 上看起来正常的演示项目，而是专门处理 Windows 10、虚拟机、远程显示、Linux 桌面主题差异下的圆角、阴影和原生窗口行为。

项目目标很明确：**窗口四个角都要圆，拖拽、缩放、贴边、最大化和复原要尽量接近系统原生行为，业务界面仍然保持 QML 的现代观感。**

## 主要特点

- **Windows + Linux 跨平台无边框窗口**：主窗口、子窗口、标题栏、页面、托盘、设置、主题和弹窗都按模块拆分，可直接作为新桌面软件的基础壳。
- **四角圆角策略**：Windows 11 正常环境优先使用系统圆角和系统阴影；Windows 10、虚拟机、Basic/Remote Display、Linux 不可信四角圆角环境使用自定义圆角窗口。
- **原生窗口行为优先**：拖拽、边缘缩放、左右半屏、上下贴边、最大化、复原、系统按钮命中区域尽量交给 native/QWindowKit 管理，避免 QML 几何补丁破坏体验。
- **外置自定义阴影**：需要自定义阴影时，不把阴影塞进内容 HWND 内部，而是用独立透明、鼠标穿透的 helper 窗口垫在后面。这样真实窗口几何仍然代表可见内容边界。
- **C++ 处理高频窗口工作**：窗口 hit-test、native 注册、外置阴影同步等高频路径由 C++/QWindowKit 处理；Python 负责配置、托盘、存储和业务桥接；QML 负责界面表现。
- **低配电脑优化方向**：页面通过 Loader 懒加载，图标使用静态 PNG，后续可通过开发者/低内存模式减少子窗口隐藏对象、Canvas/FBO 和常驻缓存。

## 运行环境

当前仓库自带 Windows x64 / Python 3.10 / PySide6 6.11 对应的 native 预编译模块。普通用户不需要安装 CMake 或 Visual Studio 就能运行。

```bash
pip install -r requirements.txt
python run.py
```

Windows 也可以使用脚本：

```bat
scripts\run_windows.bat
```

Linux 可以使用：

```bash
bash scripts/run_linux.sh
```

## 窗口策略

| 环境 | 默认策略 |
| --- | --- |
| Windows 11 正常显示环境 | 系统圆角 + 系统阴影 |
| Windows 10 | 自定义圆角 + 外置 PNG 阴影 helper |
| Windows 11 虚拟机 / Basic Display / Remote Display | 自定义圆角 + 外置 PNG 阴影 helper |
| Linux X11 且系统四角圆角不可信 | 自定义圆角，支持时使用外置阴影 fallback |
| Linux Wayland | 保守 fallback，不用脆弱的 Python 几何补丁硬修 compositor 限制 |

核心原则：**阴影不能参与真实窗口几何，真实窗口大小必须代表内容边界。** 这样贴边、半屏、最大化和上下屏才不会被阴影像素干扰。

## 项目结构

```text
run.py                              程序入口
app/main.py                         PySide6 启动、native runtime 选择
app/window_policy.py                Windows/Linux 窗口策略判断
app/bridge/                         Python <-> QML 服务桥接
app/cpp/frameless_native/           C++ native 窗口模块源码
app/native/prebuilt/                已编译 FramelessNative Qt Quick 模块
qml/window/                         AppWindow、TitleBar、窗口壳和阴影 QML
qml/controls/                       通用控件
qml/layout/                         导航和页面宿主
qml/pages/                          示例页面
resources/                          图标、阴影、托盘图标等资源
scripts/                            运行、检查和辅助脚本
third_party/qwindowkit/             vendored QWindowKit 源码
```

## QWindowKit 来源

native 无边框行为基于 QWindowKit：

https://github.com/stdware/qwindowkit

本仓库暂时把 QWindowKit 源码放在 `third_party/qwindowkit/`，方便普通用户 clone 后直接编译，不需要额外初始化 submodule。当前版本包含针对本模板右侧/底部/角落 resize 命中区域的本地调整；后续升级 QWindowKit 时需要重新核对这些补丁。

## Native 预编译模块

仓库保留了运行必需的 Windows native 预编译模块：

```text
app/native/prebuilt/win32-x64-py310-qt6.11-system/qml/FramelessNative
app/native/prebuilt/win32-x64-py310-qt6.11-custom/qml/FramelessNative
```

- `system`：用于可信系统圆角/阴影路径，例如正常 Windows 11。
- `custom`：用于 Windows 10、虚拟机、Basic Display 等需要自定义圆角和外置阴影的路径。

如果 Python、PySide6/Qt 或系统架构不同，需要重新编译 native 模块。

## 重新编译 native 模块

Windows 下优先使用项目根目录的：

```bat
b.bat
```

它会构建 `system` 和 `custom` 两套模块，并运行完整性检查。编译过程目录 `app/cpp/frameless_native/build-*` 不需要上传到仓库。

Linux 暂未提供一键脚本。需要为 Linux 重新编译时，请使用 `app/cpp/frameless_native/` 下的 CMake 工程，并把生成的 QML 模块放到 `app/native/prebuilt/` 对应平台目录。

如果没有匹配的预编译模块，程序会回退到旧的 Python/QML 窗口路径；但推荐为目标平台编译 native 模块，以获得更稳定的原生窗口行为。

## 常用接口

QML 中可以通过全局 `App` 访问配置、密文存储、主题、子窗口和托盘服务：

```qml
App.settings.valueOr("layout/navWidth", 220)
App.settings.setValue("project/name", "demo")

App.secrets.setValue("account/token", token)
App.secrets.value("account/token")

App.theme.setMode("dark")
App.theme.setPrimaryColor("#537FCD")

App.dialogs.openChild(root.Window.window, "settings", ({}))
App.tray.centerMainWindow()
```

页面代码不需要关心当前机器是系统阴影路径还是自定义阴影路径，窗口策略由 Python 和 native 层统一处理。

## 上传/发布说明

仓库不应包含：

- `user_data/` 本地配置和密文数据
- `app/cpp/frameless_native/build-*` 编译过程目录
- `*.log`、`build_output.txt`、`run_smoke.*`
- `.vscode/` 等本地编辑器配置

仓库应保留：

- Python/QML 源码
- C++ native 源码
- `third_party/qwindowkit` vendored 源码
- Windows 运行必需 native 预编译模块
- 资源文件和脚本

## 当前状态

这是一个可复用桌面软件壳，不是最终业务产品。重点在于把无边框窗口最容易出问题的部分处理稳：跨系统圆角、阴影、贴边、缩放、最大化复原、主题和多窗口基础设施。
