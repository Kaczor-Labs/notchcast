# Borrowed add-on sources

Each add-on file derived from another project is listed here, one line per file, and keeps that project's notice in its own header. An add-on branch appends its own lines and changes no other line; `notchcast/check-addons.py` enforces that in feature mode. Upstream's `NOTICE.md` ships in the app bundle and points here.

Format: `<add-on folder>: <our file> ← <source repo>/<source file> (<licence>)`, with our file relative to `Tinycast/Features/Notchcast/<add-on folder>/`.

MiddleClick: Model/ThreeFingerGesture.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/MiddleClick/MiddleClickSupport.swift (GPL-3.0-or-later)
MiddleClick: Model/MiddleClickFilter.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/MiddleClick/MiddleClickService.swift (GPL-3.0-or-later)
MiddleClick: Model/MiddleClickEngine.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/MiddleClick/MiddleClickService.swift (GPL-3.0-or-later)
MiddleClick: Service/MiddleClickTouchSource.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/MiddleClick/MiddleClickService.swift (GPL-3.0-or-later)
MiddleClick: Service/MiddleClickModule.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/MiddleClick/MiddleClickService.swift (GPL-3.0-or-later)
MusicBlock: Model/MusicLaunchTrigger.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/Audio/MusicLaunchBlocker.swift (GPL-3.0-or-later)
MusicBlock: Model/MusicLaunchPolicy.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/Audio/MusicLaunchSupport.swift (GPL-3.0-or-later)
MusicBlock: Service/MusicBlockModule.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/Audio/MusicLaunchBlocker.swift (GPL-3.0-or-later)
Screenshots: Model/ScreenshotGeometry.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/QuickTools/ScreenshotSupport.swift (GPL-3.0-or-later)
Screenshots: Model/ScreenshotExclusion.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/QuickTools/ScreenshotCapturePolicy.swift (GPL-3.0-or-later)
Screenshots: Model/ScreenshotExclusion.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/QuickTools/ScreenshotCaptureEngine.swift (GPL-3.0-or-later)
Screenshots: Service/ScreenshotSystem+Live.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/QuickTools/ScreenshotCaptureEngine.swift (GPL-3.0-or-later)
Screenshots: UI/ScreenshotSelectionSurface.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift (GPL-3.0-or-later)
DisplaySound: Model/BrightnessRecoveryPolicy.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/Display/BrightnessSupport.swift (GPL-3.0-or-later)
DisplaySound: Model/BrightnessFunctionKeys.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/Display/BrightnessSupport.swift (GPL-3.0-or-later)
DisplaySound: Service/BrightnessDisplayService.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/Display/BrightnessService.swift (GPL-3.0-or-later)
DisplaySound: Service/BrightnessController.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/Display/BrightnessService.swift (GPL-3.0-or-later)
DisplaySound: UI/BrightnessDisplayRowState.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/Display/BrightnessService.swift (GPL-3.0-or-later)
SystemTools: Model/ProcessListPolicy.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/KillProcess/KillProcessSupport.swift (GPL-3.0-or-later)
SystemTools: Model/ProcessListPolicy.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/KillProcess/KillProcessService.swift (GPL-3.0-or-later)
SystemTools: Model/ProcessListPolicy.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/Metrics/MetricFormat.swift (GPL-3.0-or-later)
SystemTools: Service/LiveProcesses.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/KillProcess/KillProcessService.swift (GPL-3.0-or-later)
SystemTools: Service/LiveProcesses.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/SystemMonitor/ProcessUsageService.swift (GPL-3.0-or-later)
SystemTools: Model/NetworkAddressPolicy.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/Metrics/NetworkAddressService.swift (GPL-3.0-or-later)
SystemTools: Model/NetworkAddressPolicy.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/Metrics/MetricFormat.swift (GPL-3.0-or-later)
SystemTools: Service/LiveNetworkAddresses.swift ← vorssaint/vorssaint-utils@89d2626/Sources/Vorssaint/Services/Metrics/NetworkAddressService.swift (GPL-3.0-or-later)
