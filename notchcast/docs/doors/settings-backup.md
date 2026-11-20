# Door: Settings backup

**Settings backup** goes through the stock format: `context.settingsBackup` (`NotchcastSettingsBackup`) gives the current settings as Backup › Export's settings JSON (capability flags such as `snippetsEnabled` already left out), calls back once on the next change to them, writes them as a settings-only `.tinycast` file atomically, and restores one through the stock import with its confirmation and report. The door is `Core/Service/NotchcastSettingsBackup.swift`; the live one is `NotchcastSettingsBackupBridge`; harnesses pass a fake, and the default writes nothing.
