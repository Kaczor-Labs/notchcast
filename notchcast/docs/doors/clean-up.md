# Door: Disk clean-up

An add-on sets `diskCleanUpTitle` on its declared `NotchcastCommand` to offer that command while space is low. Core publishes the first enabled offer in registry order through `NotchcastServices.cleanUp` and removes it when the command goes off. The offer uses the command's existing `run` and stays available when the user hides its launcher row.

The disk warning can read `context.cleanUp.title` and call `context.cleanUp.open()`. Below the configured threshold, Low Disk can offer the command on its warning, drive status and island menu. At the threshold the action clears. The drive glyph keeps its existing recovery margin and its tap returns to showing free space.
