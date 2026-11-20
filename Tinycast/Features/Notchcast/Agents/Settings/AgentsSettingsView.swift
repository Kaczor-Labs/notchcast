import AppKit
import SwiftUI

/// This Mac's name, its Claude accounts and the feed folder, under the Agents page switch.
struct AgentsSettingsView: View {
    let context: NotchcastContext
    @State private var machineName = ""
    @State private var accounts: [AgentsClaudeAccount] = []
    @State private var feedFolder: String?
    @State private var refused = false
    @FocusState private var focus: Field?
    private static let anchor = NotchcastSettingsSearch.anchor(.agents)

    private enum Field: Hashable {
        case machine
        case account(UUID)
    }

    private var preferences: AgentsPreferences { AgentsPreferences(defaults: context.defaults) }

    var body: some View {
        LabeledContent {
            TextField(text: $machineName, prompt: Text(verbatim: AgentsSystem.computerName())) {
                Text("This Mac’s name", tableName: "NotchcastAgents")
            }
            .labelsHidden()
            .focused($focus, equals: .machine)
            .onSubmit { saveMachineName() }
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("This Mac’s name", table: "NotchcastAgents"))
            Text("The title of this Mac’s column.", tableName: "NotchcastAgents")
        }
        LabeledContent {
            Button { addAccount() } label: { Text("Add…", tableName: "NotchcastAgents") }
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Claude accounts", table: "NotchcastAgents"))
            Text("Each is a Claude Code config folder, read with its own sign-in.", tableName: "NotchcastAgents")
        }
        .alert(Text("Choose a Claude Code folder", tableName: "NotchcastAgents"), isPresented: $refused) {
        } message: {
            Text("Your home folder isn’t one. Choose the folder Claude Code signs in with, such as .claude_team.",
                 tableName: "NotchcastAgents")
        }
        ForEach($accounts) { $account in
            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    TextField(text: $account.name) { Text("Name", tableName: "NotchcastAgents") }
                        .labelsHidden()
                        .focused($focus, equals: .account(account.id))
                        .onSubmit { saveAccounts() }
                    Button { remove(account) } label: { Text("Remove", tableName: "NotchcastAgents") }
                        .accessibilityLabel(Text("Remove \(account.name)", tableName: "NotchcastAgents"))
                }
            } label: {
                Text(verbatim: Self.display(account.directory.isEmpty ? "~/.claude" : account.directory))
            }
        }
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                Button { chooseFolder() } label: { Text("Choose…", tableName: "NotchcastAgents") }
                Button { save { $0.feedFolder = nil }; feedFolder = nil } label: {
                    Text("Reset", tableName: "NotchcastAgents")
                }
                .disabled(feedFolder == nil)
            }
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Feed folder", table: "NotchcastAgents"))
            Text("Reads feed.json with every Mac’s plans and writes this Mac’s to local.json.",
                 tableName: "NotchcastAgents")
            Text(verbatim: Self.display(feedFolder ?? String(localized: "Notchcast’s own folder", table: "NotchcastAgents")))
        }
        .onAppear {
            machineName = preferences.machineName ?? ""
            accounts = preferences.claudeAccounts ?? [AgentsPreferences.defaultAccount]
            feedFolder = preferences.feedFolder
        }
        // A name typed and left by a click elsewhere, or by closing Settings, is kept as Return keeps it.
        .onChange(of: focus) { left, _ in
            switch left {
            case .machine?: saveMachineName()
            case .account?: saveAccounts()
            case nil: break
            }
        }
        .onDisappear {
            if focus == .machine { saveMachineName() }
            if case .account? = focus { saveAccounts() }
        }
    }

    private static func display(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

    /// Every change reaches a running module at once, so the page follows Settings.
    private func save(_ change: (AgentsPreferences) -> Void) {
        change(preferences)
        context.module(AgentsModule.self)?.settingsChanged()
    }

    private func saveMachineName() {
        guard machineName != preferences.machineName ?? "" else { return }
        save { $0.machineName = machineName }
    }

    /// Names are the cards' titles and the feed's keys, so a blank, repeated or Codex's own one is not kept.
    private func saveAccounts() {
        var seen: Set = [AgentsSource.codex.name]
        accounts = accounts.compactMap { account in
            var account = account
            account.name = account.name.trimmingCharacters(in: .whitespaces)
            if account.name.isEmpty { account.name = AgentsPreferences.defaultAccount.name }
            while seen.contains(account.name) { account.name += " 2" }
            seen.insert(account.name)
            return account
        }
        save { $0.claudeAccounts = accounts }
    }

    private func remove(_ account: AgentsClaudeAccount) {
        accounts.removeAll { $0.id == account.id }
        saveAccounts()
    }

    private func addAccount() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let url = Self.pickFolder(from: home) else { return }
        let path = ClaudeLaunch.trimmed(url.path(percentEncoded: false))
        // With nothing selected the panel answers with the folder it shows, home at first: never a config folder.
        guard path != "/", path != ClaudeLaunch.path("~", home: home) else { return refused = true }
        guard !accounts.contains(where: { ClaudeLaunch.path($0.directory, home: home) == path }) else { return }
        let directory = path == ClaudeLaunch.path("", home: home) ? "" : path
        accounts.append(AgentsClaudeAccount(name: ClaudeLaunch.defaultName(directory: directory), directory: directory))
        saveAccounts()
    }

    private func chooseFolder() {
        guard let url = Self.pickFolder(from: feedFolder.map { URL(fileURLWithPath: $0) }) else { return }
        feedFolder = url.path(percentEncoded: false)
        save { $0.feedFolder = feedFolder }
    }

    /// Claude's config folders start with a dot, so the panel shows hidden ones.
    private static func pickFolder(from directory: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.showsHiddenFiles = true
        panel.directoryURL = directory
        return panel.runModal() == .OK ? panel.url : nil
    }
}
