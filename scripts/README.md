# Scripts

这个目录只放项目级检查、打包和辅助脚本。

## 检查

```bash
python3 scripts/check_text_encoding.py
python3 scripts/check_native_window_integrity.py --require-prebuilt --summary
```

Windows 环境也可以使用 `python`：

```bat
python scripts\check_text_encoding.py
python scripts\check_native_window_integrity.py --require-prebuilt --summary
```

`check_text_encoding.py` 用于检查中文文档、QML 和源码中的乱码风险；`check_native_window_integrity.py` 用于确认 native 预编译插件和窗口策略文件是否齐全。

## 打包

```bash
python3 scripts/package_app.py
```

```bat
python scripts\package_app.py
```

`package_app.py` 会构建 C++ UI，并复制 QML、资源、Qt runtime 和 `app/prebuilt` 里的 FramelessNative 插件到 `dist/QRoundedFrame/`。

## C++ 构建脚本位置

FramelessNative QML native 插件：

```bat
app\cpp\frameless_native\build_windows.bat
```

```bash
bash app/cpp/frameless_native/build_linux.sh
```

C++ UI 主程序：

```bat
app\cpp\ui_runtime\build_windows.bat
```

```bash
bash app/cpp/ui_runtime/build_linux.sh
```

两类脚本不要混放：一个构建 QML native 插件，一个构建主程序 exe。

## 辅助探测脚本

内存和窗口行为探测脚本只用于开发验证，例如：

```text
memory_baseline_probe.py
memory_interaction_probe.py
visual_window_probe.py
smoke_window_exit.py
```

这些脚本不是普通运行入口。日常启动仍从根目录执行 `python run.py` 或 `python3 run.py`。
