@echo off
setlocal
set "ROOT=%~dp0\..\..\.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"
set "SRC=%ROOT%\app\cpp\ui_runtime"
set "BUILD=%ROOT%\build\cpp_ui"
if defined FRAMELESS_QT_PREFIX (
    set "QT_PREFIX=%FRAMELESS_QT_PREFIX%"
) else (
    set "QT_PREFIX=Z:\Qt\6.11.1\msvc2022_64"
)
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
if not exist "%QT_PREFIX%\lib\cmake\Qt6\Qt6Config.cmake" (
    echo Qt 6 MSVC prefix not found: "%QT_PREFIX%"
    exit /b 1
)
if not exist "%CMAKE_EXE%" (
    echo CMake not found: "%CMAKE_EXE%"
    exit /b 1
)
if not exist "%NINJA_EXE%" (
    echo Ninja not found: "%NINJA_EXE%"
    exit /b 1
)
if not defined CPP_QTQUICK_HOME_BUILD_PARALLEL set "CPP_QTQUICK_HOME_BUILD_PARALLEL=1"
if exist "%BUILD%" rmdir /s /q "%BUILD%"
"%CMAKE_EXE%" -S "%SRC%" -B "%BUILD%" -G "Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="%QT_PREFIX%" -DCMAKE_MAKE_PROGRAM="%NINJA_EXE%"
if errorlevel 1 exit /b 1
"%CMAKE_EXE%" --build "%BUILD%" --config Release --parallel %CPP_QTQUICK_HOME_BUILD_PARALLEL%
if errorlevel 1 exit /b 1
echo Built: "%BUILD%\bin\QRoundedFrame.exe"
exit /b 0
