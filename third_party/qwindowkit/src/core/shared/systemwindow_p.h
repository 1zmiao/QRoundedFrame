// Copyright (C) 2023-2024 Stdware Collections (https://www.github.com/stdware)
// Copyright (C) 2021-2023 wangwenx190 (Yuhang Zhao)
// SPDX-License-Identifier: Apache-2.0

#ifndef SYSTEMWINDOW_P_H
#define SYSTEMWINDOW_P_H

//
//  W A R N I N G !!!
//  -----------------
//
// This file is not part of the QWindowKit API. It is used purely as an
// implementation detail. This header file may change from version to
// version without notice, or may even be removed.
//

#include <QtGui/QWindow>
#include <QtGui/QMouseEvent>

#include <QWKCore/private/qwkglobal_p.h>

#if defined(Q_OS_LINUX) && QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
#  include <QtGui/QGuiApplication>
#  include <QtGui/qguiapplication_platform.h>
#  include "../qwindowkit_linux.h"
#endif

namespace QWK {

    class WindowMoveManipulator : public QObject {
    public:
        explicit WindowMoveManipulator(QWindow *targetWindow)
            : QObject(targetWindow), target(targetWindow), operationComplete(false),
              initialMousePosition(QCursor::pos()),
              initialWindowPosition(targetWindow->position()) {
            target->installEventFilter(this);
        }

    protected:
        bool eventFilter(QObject *obj, QEvent *event) override {
            if (operationComplete) {
                return false;
            }
            switch (event->type()) {
                case QEvent::MouseMove: {
                    auto mouseEvent = static_cast<QMouseEvent *>(event);
                    QPoint delta = getMouseEventGlobalPos(mouseEvent) - initialMousePosition;
                    target->setPosition(initialWindowPosition + delta);
                    return true;
                }

                case QEvent::MouseButtonRelease: {
                    if (target->y() < 0) {
                        target->setPosition(target->x(), 0);
                    }
                    operationComplete = true;
                    deleteLater();
                    break;
                }

                default:
                    break;
            }
            return false;
        }

    private:
        QWindow *target;
        bool operationComplete;
        QPoint initialMousePosition;
        QPoint initialWindowPosition;
    };

    class WindowResizeManipulator : public QObject {
    public:
        WindowResizeManipulator(QWindow *targetWindow, Qt::Edges edges)
            : QObject(targetWindow), target(targetWindow), operationComplete(false),
              initialMousePosition(QCursor::pos()), initialWindowRect(target->geometry()),
              resizeEdges(edges) {
            target->installEventFilter(this);
        }

    protected:
        bool eventFilter(QObject *obj, QEvent *event) override {
            if (operationComplete) {
                return false;
            }
            switch (event->type()) {
                case QEvent::MouseMove: {
                    auto mouseEvent = static_cast<QMouseEvent *>(event);
                    QPoint globalMousePos = getMouseEventGlobalPos(mouseEvent);
                    QRect windowRect = initialWindowRect;

                    if (resizeEdges & Qt::LeftEdge) {
                        int delta = globalMousePos.x() - initialMousePosition.x();
                        windowRect.setLeft(initialWindowRect.left() + delta);
                    }
                    if (resizeEdges & Qt::RightEdge) {
                        int delta = globalMousePos.x() - initialMousePosition.x();
                        windowRect.setRight(initialWindowRect.right() + delta);
                    }
                    if (resizeEdges & Qt::TopEdge) {
                        int delta = globalMousePos.y() - initialMousePosition.y();
                        windowRect.setTop(initialWindowRect.top() + delta);
                    }
                    if (resizeEdges & Qt::BottomEdge) {
                        int delta = globalMousePos.y() - initialMousePosition.y();
                        windowRect.setBottom(initialWindowRect.bottom() + delta);
                    }

                    target->setGeometry(windowRect);
                    return true;
                }

                case QEvent::MouseButtonRelease: {
                    operationComplete = true;
                    deleteLater();
                    break;
                }

                default:
                    break;
            }
            return false;
        }

    private:
        QWindow *target;
        bool operationComplete;
        QPoint initialMousePosition;
        QRect initialWindowRect;
        Qt::Edges resizeEdges;
    };

    // QWindow::startSystemMove() and QWindow::startSystemResize() is first supported at Qt 5.15
    // QWindow::startSystemResize() returns false on macOS
    // QWindow::startSystemMove() and QWindow::startSystemResize() returns false on Linux Unity DE

    // When the new API fails, we emulate the window actions using the classical API.

#if defined(Q_OS_LINUX) && QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
    inline bool startX11SystemMove(QWindow *window) {
        if (!window || !QWK::Private::isX11Platform())
            return false;
        auto *x11app = qGuiApp ? qGuiApp->nativeInterface<QNativeInterface::QX11Application>() : nullptr;
        if (!x11app)
            return false;
        auto *display = x11app->display();
        if (!display)
            return false;
        const auto &api = QWK::Private::x11API();
        if (!api.isValid())
            return false;

        constexpr auto None = 0L;
        constexpr auto ClientMessage = 33;
        constexpr auto False = 0;
        constexpr auto SubstructureNotifyMask = 1L << 19;
        constexpr auto SubstructureRedirectMask = 1L << 20;
        constexpr auto CurrentTime = 0L;
        constexpr auto NetWmMove = 8L;
        constexpr auto Button1 = 1L;
        constexpr auto SourceApplication = 1L;

        using XClientMessageEvent = struct {
            int type;
            unsigned long serial;
            Bool send_event;
            Display *display;
            Window window;
            Atom message_type;
            int format;
            union {
                char b[20];
                short s[10];
                long l[5];
            } data;
        };
        union XEventCompat {
            XClientMessageEvent xclient;
            long pad[24];
        };

        const Atom atom = api.XInternAtom(display, "_NET_WM_MOVERESIZE", False);
        if (atom == None)
            return false;

        const QPoint cursor = QCursor::pos();
        XEventCompat event{};
        event.xclient.type = ClientMessage;
        event.xclient.window = static_cast<Window>(window->winId());
        event.xclient.message_type = atom;
        event.xclient.format = 32;
        event.xclient.data.l[0] = cursor.x();
        event.xclient.data.l[1] = cursor.y();
        event.xclient.data.l[2] = NetWmMove;
        event.xclient.data.l[3] = Button1;
        event.xclient.data.l[4] = SourceApplication;

        api.XUngrabPointer(display, CurrentTime);
        const Window targetRoot = api.XDefaultRootWindow(display);
        if (!targetRoot)
            return false;
        api.XSendEvent(display, targetRoot, False, SubstructureRedirectMask | SubstructureNotifyMask,
                       reinterpret_cast<XEvent *>(&event));
        api.XFlush(display);
        return true;
    }
#endif

    inline void startSystemMove(QWindow *window) {
        Q_ASSERT(window);
#if (QT_VERSION < QT_VERSION_CHECK(5, 15, 0))
        std::ignore = new WindowMoveManipulator(window);
#elif defined(Q_OS_LINUX)
        if (startX11SystemMove(window)) {
            return;
        }
        if (window->startSystemMove()) {
            return;
        }
        std::ignore = new WindowMoveManipulator(window);
#else
        window->startSystemMove();
#endif
    }

    inline void startSystemResize(QWindow *window, Qt::Edges edges) {
        Q_ASSERT(window);
#if (QT_VERSION < QT_VERSION_CHECK(5, 15, 0))
        std::ignore = new WindowResizeManipulator(window, edges);
#elif defined(Q_OS_MAC) || defined(Q_OS_LINUX)
        if (window->startSystemResize(edges)) {
            return;
        }
        std::ignore = new WindowResizeManipulator(window, edges);
#else
        window->startSystemResize(edges);
#endif
    }

}

#endif // SYSTEMWINDOW_P_H
