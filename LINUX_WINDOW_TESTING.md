# Linux 窗口测试与交接

这份文档用于把当前 Windows 主线迁到 Linux 时交接窗口行为、阴影、内存口径和编译事项。

## 当前主线

- UI 主线是 C++ Qt Quick + QML，不再是 PySide6 UI 常驻。
- C++ UI 主程序源码在 `app/cpp/ui_runtime/`。
- FramelessNative 窗口插件源码在 `app/cpp/frameless_native/`。
- 预编译插件统一放在 `app/prebuilt/`。
- Python 只作为业务 worker 示例，不负责 UI 入口和窗口壳。

## Linux 是否需要重新编译

需要。Windows 的 native 插件不能直接给 Linux 用。

编译 FramelessNative：

```bash
bash app/cpp/frameless_native/build_linux.sh
```

如果 Qt 不在系统默认位置：

```bash
FRAMELESS_QT_PREFIX=/opt/Qt/6.11.1/gcc_64 bash app/cpp/frameless_native/build_linux.sh
```

期望输出：

```text
app/prebuilt/linux-x64-qt6.11-system/qml/FramelessNative
app/prebuilt/linux-x64-qt6.11-custom/qml/FramelessNative
```

编译 C++ UI 主程序也需要在 Linux 上补对应脚本或 CMake preset；不要复用 Windows exe。

编译后先跑：

```bash
python scripts/check_native_window_integrity.py --require-prebuilt --summary --tag linux-x64-qt6.11
```

## Linux 内存口径

Linux 上用户可见的“当前私有驻留内存”应优先按 USS 理解。

`app/memory_snapshot.py` 在 Linux 下优先读取 `/proc/self/smaps_rollup`：

- `rss`：驻留内存。
- `uss`：Unique Set Size，进程独占的驻留内存。
- `pss`：共享页按比例折算。
- `private`：Linux 下映射为 USS。
- `ws_private`：为了复用 Windows UI 字段，Linux 下也映射为 USS。

Windows 的 Working Set - Private 和 Linux USS 不是同一个内核指标，但在用户感知上最接近。

C++ UI 启动早期会设置 Linux allocator：

```text
mallopt(M_TRIM_THRESHOLD, 128 * 1024)
mallopt(M_MMAP_THRESHOLD, 128 * 1024)
mallopt(M_ARENA_MAX, 2)
```

如果平台支持，保留这些设置；它们用于降低 Linux 常驻内存，不要轻易删除。

## Linux 阴影遗留问题

之前 Linux 自定义阴影仍有这些问题需要在目标系统修：

1. 缩放左上角窗口时，底部和右侧阴影抖动。
2. 阴影虽然在本软件窗口下面，但会被其他系统级窗口盖住。
3. 窗口移出屏幕外时，阴影被限制在屏幕内，不能跟随主窗口越界。

这些更像 Linux 窗口管理器/合成器对外置阴影窗口的层级和位置约束，不是 QML 内容层问题。

优先排查方向：

- X11 下检查 shadow helper 是否设置合适的 transient、override-redirect、type hint。
- 阴影窗口不要设置会被 WM 限制在 workarea 内的普通顶层窗口属性。
- 阴影跟随 frame geometry，不要跟随 client geometry。
- 不要用高频 QML timer 追阴影位置，优先接 native configure/geometry 事件。
- Wayland 下外置阴影窗口位置和层级通常不可可靠控制；如果复现这些问题，建议该会话禁用 custom external shadow，回退系统窗口/系统阴影。

## 测试环境记录

每个 Linux 桌面都记录：

```bash
echo $XDG_SESSION_TYPE
echo $XDG_CURRENT_DESKTOP
echo $XDG_SESSION_DESKTOP
echo $DESKTOP_SESSION
echo $WINDOW_MANAGER
python -c "from app.window_policy import current_window_policy; print(current_window_policy())"
```

建议测试顺序：

1. GNOME Wayland：默认保守，通常不建议 custom external shadow。
2. GNOME on Xorg：可强制 custom 做对比，但不要默认启用。
3. XFCE / xfwm4：适合优先验证 Linux custom chrome。
4. Cinnamon / muffin：可测。
5. KDE Plasma X11 / kwin_x11：用户多，但窗口规则复杂，需要单独验证。

## 白名单策略

默认不要把 Linux custom chrome 做成全局开启。

只在某个窗口管理器完整通过后，再加入白名单。判断对象应是窗口管理器和会话类型，不是发行版名称。

## 必测项

系统窗口默认路径：

- 主窗口启动、移动、缩放、最小化、最大化、关闭正常。
- 自绘标题栏内容不和系统标题栏按钮冲突。
- 主题切换、右键菜单、滚动、输入框、任务列表正常。

强制 custom chrome 路径：

- 四边和四角缩放命中区正确。
- 左上角缩放时右侧/底部边界不漏底、不反复抖。
- 阴影跟随窗口，不抢焦点、不挡点击、不乱飞。
- 最大化、半屏、恢复符合当前桌面环境习惯。
- 多屏、不同缩放比例下无明显错位。

## 不要动的 Windows 稳定路径

Linux 调试时不要顺手改这些 Windows 稳定文件，除非明确修 Windows：

```text
app/cpp/ui_runtime/src
app/cpp/frameless_native/src/native_window_agent.cpp
app/cpp/frameless_native/src/external_shadow_controller.cpp
app/prebuilt/win-x64-qt6.11-custom
app/prebuilt/win-x64-qt6.11-system
```

Linux 优先改动范围：

```text
app/cpp/frameless_native/build_linux.sh
app/cpp/frameless_native/src 中经 Linux 实测确认的跨平台/native 代码
app/prebuilt/linux-x64-qt6.11-*
```

## 优化理念

- 不要用高频 timer 追窗口或阴影位置。
- 能用系统窗口行为时优先系统窗口行为。
- 外置阴影必须跟随 native geometry 事件，不依赖 QML 下一帧。
- 大列表继续使用模型虚拟化，不用 Repeater 展开大量条目。
- 内存显示优先看 USS；RSS 包含共享库和 Qt/显存相关驻留，不能直接等价于 Windows Working Set - Private。
