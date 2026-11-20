# Door: Apple Events

**Apple Events** to another app go through `NotchcastAppleEvents` (`Core/Service/`): `values(bundleID, path, refusing:)` sends one `core/getd` read, 5 s, and `finderSelection(refusing:)` returns Finder's selection as file URLs. Both are synchronous, so the add-on calls them off the main actor. A failed read hands its status to the add-on's `refusing` closure and reads as empty unless that throws, so each add-on keeps its own failure states. It is in Core because Copy Path and Taildrop both read Finder (§1: two folders never share code).
