#pragma once

// Linux-only helper declarations for native_window_agent.
// Must only be included inside #if defined(Q_OS_LINUX) && defined(FRAMELESS_NATIVE_HAS_X11_SHAPE)
// after X11 headers (X11/Xlib.h, X11/X.h, X11/extensions/shape.h).

#include <QtCore/QMargins>
#include <QtCore/QSize>
#include <QtCore/QString>

class QQuickWindow;
class QWindow;

// X11 types from includer context (must be available via prior X11 includes)

Display *sharedXDisplay();
bool canUseX11Shape();
qreal normalizedDpr(qreal dpr);
int nativeCornerRadiusPx(int radius, qreal dpr);
int nativePx(int value, qreal dpr);
QSize nativeSizePx(const QSize &size, qreal dpr);
QSize x11WindowSizePx(Display *display, Window window);
bool dprTraceEnabled();
qreal readXftDpiDpr(Display *display);
qreal readKdeScaleFactorDpr();
XRectangle makeRect(short x, short y, unsigned short width, unsigned short height);
void setGtkFrameExtentsForWindow(QWindow *window, const QMargins &margins, qreal dpr);
QString linuxDesktopText();
bool desktopNeedsNormalWindowType();
void setX11NormalWindowTypeForDesktop(QWindow *window);
bool sendNetWmMoveResize(QWindow *window);
void releaseQtMouseGrab(QQuickWindow *window);
bool prefersEwmhSystemMove();
bool desktopIsXfce();
