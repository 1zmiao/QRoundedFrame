class NativeWindowHelper:
    """Pure Python fallback placeholder.

    Add a compiled helper named app/native/frameless_native.* later and keep the
    same method names to upgrade shadows, native hit-testing, and platform quirks.
    """

    def install_window(self, window_id: int, options: dict | None = None) -> bool:
        return False

    def set_always_on_top(self, window_id: int, enabled: bool) -> bool:
        return False

    def set_shadow_enabled(self, window_id: int, enabled: bool) -> bool:
        return False

    def set_corner_radius(self, window_id: int, radius: int) -> bool:
        return False

    def set_hit_test_margins(self, window_id: int, left: int, top: int, right: int, bottom: int) -> bool:
        return False
