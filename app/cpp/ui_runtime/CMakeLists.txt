cmake_minimum_required(VERSION 3.21)
project(QRoundedFrame LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Sql Concurrent Widgets)
if(UNIX AND NOT APPLE)
    find_package(X11)
    find_package(PkgConfig)
    if(PkgConfig_FOUND)
        pkg_check_modules(LIBSECRET libsecret-1)
    endif()
endif()

set(QROUNDEDFRAME_UI_SOURCES
    src/main.cpp
    src/runtime_app.h
    src/runtime_app.cpp
    src/task_store.h
    src/task_store.cpp
    src/card_glow_provider.h
    src/card_glow_provider.cpp
)

if(WIN32)
    list(APPEND QROUNDEDFRAME_UI_SOURCES resources/windows_app.rc)
    add_executable(QRoundedFrame WIN32 ${QROUNDEDFRAME_UI_SOURCES})
else()
    add_executable(QRoundedFrame ${QROUNDEDFRAME_UI_SOURCES})
endif()

target_link_libraries(QRoundedFrame PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Sql
    Qt6::Concurrent
    Qt6::Widgets
)

if(UNIX AND NOT APPLE AND X11_FOUND)
    target_compile_definitions(QRoundedFrame PRIVATE QROUNDEDFRAME_HAS_X11=1)
    target_include_directories(QRoundedFrame PRIVATE ${X11_INCLUDE_DIR})
    target_link_libraries(QRoundedFrame PRIVATE ${X11_LIBRARIES})
endif()

if(UNIX AND NOT APPLE AND LIBSECRET_FOUND)
    target_compile_definitions(QRoundedFrame PRIVATE QROUNDEDFRAME_HAS_LIBSECRET=1)
    target_include_directories(QRoundedFrame PRIVATE ${LIBSECRET_INCLUDE_DIRS})
    target_link_directories(QRoundedFrame PRIVATE ${LIBSECRET_LIBRARY_DIRS})
    target_link_libraries(QRoundedFrame PRIVATE ${LIBSECRET_LIBRARIES})
endif()

if(WIN32)
    target_link_libraries(QRoundedFrame PRIVATE Crypt32)
endif()

set_target_properties(QRoundedFrame PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
