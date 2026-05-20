try:
    from .frameless_native import NativeWindowHelper  # type: ignore
except Exception:
    from .fallback import NativeWindowHelper

native = NativeWindowHelper()
