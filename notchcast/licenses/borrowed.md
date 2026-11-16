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
