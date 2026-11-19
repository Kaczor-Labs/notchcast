/// Every add-on, one line each; deleting an add-on is its folder plus its line here.
@MainActor
enum NotchcastRegistry {
    static let addons: [any NotchcastAddon.Type] = [
        HideCommandMAddon.self,
        ShowDesktopAddon.self,
        QuitProtectionAddon.self,
        MiddleClickAddon.self,
        MusicBlockAddon.self,
        NumberKeysAddon.self,
        SmallCommandsAddon.self,
        DownloadsAddon.self,
        ScreenshotsAddon.self,
        IPhoneBackupAddon.self,
        DisplaySoundAddon.self,
        NoiseControlAddon.self,
        AutoBackupAddon.self,
        PastePlainTextAddon.self,
        ColorPickerAddon.self,
        CopyPathAddon.self,
        FinderToolsAddon.self,
    ]
}
