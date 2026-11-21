import Foundation

extension AppCore {
    func notchcastSettingsStatus() -> NotchcastSettingsStatus {
        var status = NotchcastSettingsStatus()
        if let scripts = settingsModule(ScriptCommandsModule.self, for: ScriptCommandsAddon.switchID) {
            status.scripts = .init(rows: scripts.rows, running: scripts.running, outputRevisions: scripts.outputRevisions)
        }
        status.displays = settingsModule(DisplaySoundModule.self, for: DisplaySoundAddon.brightnessID)?
            .brightness.currentDisplays
        if let downloads = settingsModule(DownloadsModule.self, for: DownloadsModule.torrentsSwitchID) {
            status.torrents = .init(jobs: downloads.torrents.jobs.map(NotchcastSettingsStatus.Torrents.Job.init),
                                    bonded: downloads.bonding.torrentsBonded)
        }
        if let spotify = settingsModule(SpotifyModule.self, for: SpotifyAddon.switchID) {
            status.spotify = .init(
                build: spotify.build, phase: spotify.phase, hasKey: spotify.hasKey,
                installing: spotify.installing, installError: spotify.installError, clientID: spotify.clientID,
                isSignedIn: spotify.isSignedIn, signingIn: spotify.signingIn, signInFailed: spotify.signInError != nil)
        }
        if let iPhone = settingsModule(IPhoneBackupModule.self, for: IPhoneBackupAddon.switchID) {
            status.iPhoneBackup = .init(isApplied: iPhone.isApplied, backupsOff: iPhone.backupsOff)
        }
        status.dictationCleanupModel = dictationExtras.cleanupModel
        status.dictationAutomaticModelTitle = dictationExtras.automaticModel?.title
        status.hasDictationHistory = !dictationExtras.history.entries.isEmpty
        return status
    }

    func performNotchcastSettingsAction(_ action: NotchcastSettingsAction) {
        switch action {
        case .addScript(let id):
            settingsModule(ScriptCommandsModule.self, for: ScriptCommandsAddon.switchID)?.addRow(id: id)
        case .updateScript(let row):
            settingsModule(ScriptCommandsModule.self, for: ScriptCommandsAddon.switchID)?.update(row)
        case .deleteScript(let id):
            settingsModule(ScriptCommandsModule.self, for: ScriptCommandsAddon.switchID)?.removeRow(id)
        case .refreshAgents:
            settingsModule(AgentsModule.self, for: AgentsPreferences.switchID)?.settingsChanged()
        case .torrent(let id, let action):
            guard let downloads = settingsModule(DownloadsModule.self, for: DownloadsModule.torrentsSwitchID),
                  let job = downloads.torrents.jobs.first(where: { $0.id == id }) else { return }
            switch action {
            case .reveal: downloads.torrents.reveal(job.files)
            case .cancel: downloads.torrents.cancel(id)
            case .retry: downloads.retryTorrent(id)
            case .dismiss: downloads.torrents.dismiss(id)
            }
        case .setArchiveDefault(let enabled):
            settingsModule(ArchivesModule.self, for: ArchivesModule.switchID)?.setDefaultApp(enabled)
        case .checkLowDisk:
            settingsModule(LowDiskModule.self, for: "lowDiskWarning")?.check()
        case .setDaySymbols(let text):
            settingsModule(DayModule.self, for: "dayPage")?.setSymbols(text)
        case .installSoloist:
            guard let spotify = settingsModule(SpotifyModule.self, for: SpotifyAddon.switchID) else { return }
            Task { await spotify.install() }
        case .removeSoloistKey:
            settingsModule(SpotifyModule.self, for: SpotifyAddon.switchID)?.removeKey()
        case .setSpotifyClientID(let clientID):
            settingsModule(SpotifyModule.self, for: SpotifyAddon.switchID)?.setClientID(clientID)
        case .signInSpotify(let clientID):
            guard let spotify = settingsModule(SpotifyModule.self, for: SpotifyAddon.switchID) else { return }
            spotify.setClientID(clientID)
            Task { await spotify.signIn() }
        case .signOutSpotify:
            settingsModule(SpotifyModule.self, for: SpotifyAddon.switchID)?.signOut()
        case .copyColor(let red, let green, let blue, let alpha):
            settingsModule(ColorPickerModule.self, for: ColorPickerModule.switchID)?
                .copy(ColorValue(red: red, green: green, blue: blue, alpha: alpha))
        case .selectDictationCleanupModel(let selection):
            dictationExtras.selectCleanupModel(selection)
        case .restoreAutomaticBackup(let file):
            Task { await NotchcastSettingsBackupBridge(core: self).restore(file) }
        case .answerIPhoneBackup(let accepted):
            settingsModule(IPhoneBackupModule.self, for: IPhoneBackupAddon.switchID)?.answer(accepted)
        }
    }

    func performNotchcastSettingsCall(_ call: NotchcastSettingsCall) async throws -> NotchcastSettingsReply {
        switch call {
        case .setBrightness(let value, let display):
            let brightness = settingsModule(DisplaySoundModule.self, for: DisplaySoundAddon.brightnessID)?.brightness
            return .brightness(await brightness?.set(value, for: display))
        case .scriptOutput(let id):
            return .scriptOutput(settingsModule(ScriptCommandsModule.self, for: ScriptCommandsAddon.switchID)?.outputs[id])
        case .inspectTorrents:
            let id = DownloadsModule.torrentsSwitchID
            guard let downloads = settingsModule(DownloadsModule.self, for: id) else { throw CancellationError() }
            let handler = notchcast?.controller.context(forSwitch: id)?.recovery(TorrentOpenFallback.self)?.defaultApp
            return .torrentTools(aria2c: downloads.environment.tools.find(.aria2c),
                                 defaultApps: handler?.defaultAppNames ?? [])
        case .setDayCity(let city):
            guard let day = settingsModule(DayModule.self, for: "dayPage") else { throw CancellationError() }
            guard await day.setCity(city) else { return .dayCity(nil) }
            return .dayCity(day.place?.name ?? "")
        case .saveSoloistKey(let key):
            guard let spotify = settingsModule(SpotifyModule.self, for: SpotifyAddon.switchID)
            else { throw CancellationError() }
            try spotify.setKey(key)
            return .soloistKeySaved
        }
    }

    private func settingsModule<M: NotchcastModule>(_ type: M.Type, for id: String) -> M? {
        guard let controller = notchcast?.controller, controller.preferences.isEnabled(id) else { return nil }
        return controller.context(forSwitch: id)?.module(type)
    }
}
