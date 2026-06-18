@echo off
setlocal
set "ROOT=%~dp0\..\..\.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"
set "EXE=%ROOT%\build\cpp_ui\bin\QRoundedFrame.exe"
if defined FRAMELESS_QT_PREFIX (
    set "QT_PREFIX=%FRAMELESS_QT_PREFIX%"
) else (
    set "QT_PREFIX=Z:\Qt\6.11.1\msvc2022_64"
)
set "NATIVE_PLUGIN_DIR=%ROOT%\app\prebuilt\win-x64-qt6.11-custom\qml\FramelessNative"

if not exist "%EXE%" (
    call "%ROOT%\app\cpp\ui_runtime\build_windows.bat"
    if errorlevel 1 exit /b 1
)

if not exist "%QT_PREFIX%\bin\Qt6Core.dll" (
    echo Qt runtime not found: "%QT_PREFIX%"
    exit /b 1
)

set "PATH=%QT_PREFIX%\bin;%NATIVE_PLUGIN_DIR%;%PATH%"
pushd "%ROOT%"
"%EXE%" %*
set "CODE=%ERRORLEVEL%"
popd
exit /b %CODE%
