# Scripts

这个目录只放项目级检查、打包和辅助脚本。

## 项目级脚本

```bat
python scripts\check_text_encoding.py
python scripts\check_native_window_integrity.py --require-prebuilt --summary
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

两类脚本不要混放：一个构建 QML native 插件，一个构建主程序 exe。
