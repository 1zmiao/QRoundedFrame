@echo off
setlocal
set "ROOT=%~dp0\..\..\.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI\"
if defined FRAMELESS_QT_PREFIX (
    set "QT_PREFIX=%FRAMELESS_QT_PREFIX%"
) else (
    set "QT_PREFIX=Z:\Qt\6.11.1\msvc2022_64"
)
set "SRC=%ROOT%app\cpp\frameless_native"
set "PREBUILT_ROOT=%ROOT%app\prebuilt"
set "TAG=win-x64-qt6.11"
set "VS_ROOT=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
set "VCVARS=%VS_ROOT%\VC\Auxiliary\Build\vcvars64.bat"
set "CMAKE_DIR=%VS_ROOT%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
set "NINJA_DIR=%VS_ROOT%\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja"
if not exist "%CMAKE_DIR%\cmake.exe" set "CMAKE_DIR=Z:\Qt\Tools\CMake_64\bin"
if not exist "%NINJA_DIR%\ninja.exe" set "NINJA_DIR=Z:\Qt\Tools\Ninja"
set "CMAKE_EXE=%CMAKE_DIR%\cmake.exe"
set "NINJA_EXE=%NINJA_DIR%\ninja.exe"
if exist "%VCVARS%" call "%VCVARS%"
set "PATH=%CMAKE_DIR%;%NINJA_DIR%;%QT_PREFIX%\bin;%PATH%"
set "CC="
set "CXX="
python "%ROOT%scripts\check_native_window_integrity.py"
if errorlevel 1 goto :fail
if not exist "%QT_PREFIX%\lib\cmake\Qt6\Qt6Config.cmake" (
    echo Qt 6 MSVC prefix not found: "%QT_PREFIX%"
    goto :fail
)
if not exist "%CMAKE_EXE%" (
    echo CMake not found: "%CMAKE_EXE%"
    goto :fail
)
if not exist "%NINJA_EXE%" (
    echo Ninja not found: "%NINJA_EXE%"
    goto :fail
)
echo Using Qt: "%QT_PREFIX%"
echo Using CMake: "%CMAKE_EXE%"
echo Using Ninja: "%NINJA_EXE%"
call :build_variant system ON
if errorlevel 1 goto :fail
call :build_variant custom OFF
if errorlevel 1 goto :fail
python "%ROOT%scripts\check_native_window_integrity.py" --require-prebuilt --summary
if errorlevel 1 goto :fail
echo Built FramelessNative variants:
echo   "%PREBUILT_ROOT%\%TAG%-system\qml\FramelessNative"
echo   "%PREBUILT_ROOT%\%TAG%-custom\qml\FramelessNative"
if not defined FRAMELESS_NO_PAUSE pause
exit /b 0

:build_variant
set "VARIANT=%~1"
set "SYSTEM_BORDERS=%~2"
set "BUILD=%ROOT%build\frameless_native\win-%VARIANT%"
set "PREBUILT=%PREBUILT_ROOT%\%TAG%-%VARIANT%"
echo Building %VARIANT% native module. QWINDOWKIT_ENABLE_WINDOWS_SYSTEM_BORDERS=%SYSTEM_BORDERS%
if exist "%BUILD%" rmdir /s /q "%BUILD%"
if exist "%PREBUILT%\qml\FramelessNative" rmdir /s /q "%PREBUILT%\qml\FramelessNative"
"%CMAKE_EXE%" -S "%SRC%" -B "%BUILD%" -G "Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="%QT_PREFIX%" -DCMAKE_MAKE_PROGRAM="%NINJA_EXE%" -DFRAMELESS_NATIVE_QML_OUTPUT_DIR="%PREBUILT%\qml" -DQWINDOWKIT_ENABLE_WINDOWS_SYSTEM_BORDERS=%SYSTEM_BORDERS%
if errorlevel 1 exit /b 1
"%CMAKE_EXE%" --build "%BUILD%" --config Release
if errorlevel 1 exit /b 1
del /q "%PREBUILT%\qml\FramelessNative\FramelessNativeplugin.lib" "%PREBUILT%\qml\FramelessNative\FramelessNativeplugin.exp" "%PREBUILT%\qml\FramelessNative\FramelessNative_qml_module_dir_map.qrc" "%PREBUILT%\qml\FramelessNative\FramelessNative_qml_module_dir_map_rc.py" 2>nul
exit /b 0

:fail
if not defined FRAMELESS_NO_PAUSE pause
exit /b 1
