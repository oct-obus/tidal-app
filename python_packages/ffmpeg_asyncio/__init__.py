"""
ffmpeg_asyncio shim for iOS - no ffmpeg available on iOS.
Provides the FFmpeg class interface but operations are no-ops.
"""


class FFmpeg:
    def __init__(self):
        self._callbacks = {}

    def option(self, *args, **kwargs):
        return self

    def input(self, *args, **kwargs):
        return self

    def output(self, *args, **kwargs):
        return self

    def on(self, event):
        def decorator(func):
            self._callbacks[event] = func
            return func
        return decorator

    async def execute(self):
        if "completed" in self._callbacks:
            self._callbacks["completed"]()


class types:
    Option = str
