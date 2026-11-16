import AppKit
import SwiftUI

/// One control per row, so the core's grouped Form lays each out as its own line.
enum KeepAwakeSettingsRows {
    typealias Key = KeepAwakeSettings.Key

    static var all: [@MainActor @Sendable (NotchcastContext) -> AnyView] {
        [
            { AnyView(KeepAwakeDurationRow(context: $0)) },
            { AnyView(KeepAwakeFloorRow(context: $0)) },
            { AnyView(KeepAwakeToggleRow(
                context: $0, key: Key.pausesWhenLocked,
                title: LocalizedStringResource("Pause while the screen is locked", table: "NotchcastKeepAwake"),
                subtitle: Text("Lets the Mac sleep while it's locked.", tableName: "NotchcastKeepAwake"))) },
            { AnyView(KeepAwakeToggleRow(
                context: $0, key: Key.restoresSession, defaultValue: true,
                title: LocalizedStringResource("Resume after Notchcast restarts", table: "NotchcastKeepAwake"),
                subtitle: Text("A session that was on picks up where it left off.", tableName: "NotchcastKeepAwake"))) },
            { AnyView(KeepAwakeToggleRow(
                context: $0, key: Key.autoDisplay,
                title: LocalizedStringResource("Turn on with an external display", table: "NotchcastKeepAwake"),
                subtitle: Text("Stays on while a display is connected.", tableName: "NotchcastKeepAwake"))) },
            { AnyView(KeepAwakeToggleRow(
                context: $0, key: Key.autoPower,
                title: LocalizedStringResource("Turn on when plugged in", table: "NotchcastKeepAwake"),
                subtitle: Text("Stays on while the Mac runs on power.", tableName: "NotchcastKeepAwake"))) },
            { AnyView(KeepAwakeToggleRow(
                context: $0, key: Key.autoApps,
                title: LocalizedStringResource("Turn on while chosen apps run", table: "NotchcastKeepAwake"),
                subtitle: Text("Stays on while any app below is open.", tableName: "NotchcastKeepAwake"))) },
            { AnyView(KeepAwakeAppsRow(context: $0)) },
            { AnyView(KeepAwakeRequiresAllRow(context: $0)) }
        ]
    }

    @MainActor
    static func changed(_ context: NotchcastContext) {
        context.module(KeepAwakeModule.self)?.settingsChanged()
    }
}

private struct KeepAwakeDurationRow: View {
    let context: NotchcastContext
    @AppStorage private var minutes: Int

    init(context: NotchcastContext) {
        self.context = context
        _minutes = AppStorage(
            wrappedValue: KeepAwakeSettings.defaultMinutes, KeepAwakeSettings.Key.minutes, store: context.defaults)
    }

    var body: some View {
        Picker(selection: $minutes) {
            ForEach(KeepAwakeSettings.durations, id: \.self) { value in
                if value == 0 {
                    Text("Until turned off", tableName: "NotchcastKeepAwake").tag(value)
                } else {
                    Text(Duration.seconds(value * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide)))
                        .tag(value)
                }
            }
        } label: {
            SettingsRowTitle(
                NotchcastSettingsSearch.anchor(.power),
                LocalizedStringResource("Duration", table: "NotchcastKeepAwake"))
            Text("How long Keep Awake stays on once you turn it on.", tableName: "NotchcastKeepAwake")
        }
        .onChange(of: minutes) { KeepAwakeSettingsRows.changed(context) }
    }
}

private struct KeepAwakeFloorRow: View {
    let context: NotchcastContext
    @AppStorage private var floor: Int

    init(context: NotchcastContext) {
        self.context = context
        _floor = AppStorage(
            wrappedValue: KeepAwakeSettings.defaultFloor, KeepAwakeSettings.Key.floor, store: context.defaults)
    }

    var body: some View {
        Picker(selection: $floor) {
            ForEach(KeepAwakeSettings.floors, id: \.self) { value in
                if value == 0 {
                    Text("Never", tableName: "NotchcastKeepAwake").tag(value)
                } else {
                    Text(Double(value) / 100, format: .percent).tag(value)
                }
            }
        } label: {
            SettingsRowTitle(
                NotchcastSettingsSearch.anchor(.power),
                LocalizedStringResource("Stop on battery below", table: "NotchcastKeepAwake"))
            Text("On battery, Keep Awake turns off below this charge.", tableName: "NotchcastKeepAwake")
        }
        .onChange(of: floor) { KeepAwakeSettingsRows.changed(context) }
    }
}

private struct KeepAwakeToggleRow: View {
    let context: NotchcastContext
    let title: LocalizedStringResource
    let subtitle: Text
    @AppStorage private var isOn: Bool

    init(
        context: NotchcastContext, key: String, defaultValue: Bool = false,
        title: LocalizedStringResource, subtitle: Text
    ) {
        self.context = context
        self.title = title
        self.subtitle = subtitle
        _isOn = AppStorage(wrappedValue: defaultValue, key, store: context.defaults)
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsRowTitle(NotchcastSettingsSearch.anchor(.power), title)
            subtitle
        }
        .onChange(of: isOn) { KeepAwakeSettingsRows.changed(context) }
    }
}

/// The chosen apps as a list; new ones come from the apps running now.
private struct KeepAwakeAppsRow: View {
    let context: NotchcastContext
    @AppStorage private var watchesApps: Bool
    @State private var bundleIDs: [String]
    @State private var adding: KeepAwakeAppRequest?

    init(context: NotchcastContext) {
        self.context = context
        _watchesApps = AppStorage(wrappedValue: false, KeepAwakeSettings.Key.autoApps, store: context.defaults)
        _bundleIDs = State(initialValue: context.defaults.stringArray(forKey: KeepAwakeSettings.Key.autoBundleIDs) ?? [])
    }

    var body: some View {
        if watchesApps {
            Group {
                if bundleIDs.isEmpty {
                    Text("No apps chosen", tableName: "NotchcastKeepAwake")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bundleIDs.map { KeepAwakeAppChoice(id: $0) }) { app in
                        SettingsRow(title: app.name) {
                            KeepAwakeAppIcon(path: app.path)
                        } trailing: {
                            Button { remove(app.id) } label: {
                                SymbolImage(name: "trash", size: Theme.Size.settingsRowIcon)
                                    .foregroundStyle(Theme.Colors.destructive)
                            }
                            .buttonStyle(.plain)
                            .help(Text("Remove \(app.name)", tableName: "NotchcastKeepAwake"))
                            .accessibilityLabel(Text("Remove \(app.name)", tableName: "NotchcastKeepAwake"))
                        }
                    }
                }
                Button {
                    let chosen = Set(bundleIDs)
                    adding = KeepAwakeAppRequest(choices: KeepAwakeAppChoice.running().filter { !chosen.contains($0.id) })
                } label: {
                    SettingsRowTitle(
                        NotchcastSettingsSearch.anchor(.power),
                        LocalizedStringResource("Add Apps", table: "NotchcastKeepAwake"))
                }
            }
            .settingsEditorPanel(item: $adding) { request in
                KeepAwakeAppPanel(choices: request.choices) { add($0) }
            }
        }
    }

    private func add(_ ids: [String]) {
        save(bundleIDs + ids.filter { !bundleIDs.contains($0) })
    }

    private func remove(_ id: String) {
        save(bundleIDs.filter { $0 != id })
    }

    private func save(_ ids: [String]) {
        bundleIDs = ids
        context.defaults.set(ids, forKey: KeepAwakeSettings.Key.autoBundleIDs)
        KeepAwakeSettingsRows.changed(context)
    }
}

private struct KeepAwakeAppRequest: Identifiable {
    let id = UUID()
    let choices: [KeepAwakeAppChoice]
}

private struct KeepAwakeAppPanel: View {
    @Environment(\.settingsEditorDismiss) private var dismiss
    let choices: [KeepAwakeAppChoice]
    let onAdd: ([String]) -> Void
    @State private var picked: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsEditorHeader(
                title: LocalizedStringResource("Add Apps", table: "NotchcastKeepAwake"),
                subtitle: LocalizedStringResource(
                    "Keep Awake stays on while any chosen app is open.", table: "NotchcastKeepAwake"))
            if choices.isEmpty {
                Text("Open the app you want, then add it here.", tableName: "NotchcastKeepAwake")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ForEach(choices) { app in
                            Toggle(isOn: binding(for: app.id)) {
                                Label {
                                    Text(app.name)
                                } icon: {
                                    KeepAwakeAppIcon(path: app.path)
                                }
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: Theme.Size.editorTextHeight * 2)
            }
            HStack(spacing: Theme.Spacing.md) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    onAdd(choices.map(\.id).filter(picked.contains))
                    dismiss()
                }
                .buttonStyle(.modalAction(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(picked.isEmpty)
            }
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: Theme.Size.editorSheetWidth)
        .settingsEditorPanelSurface()
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { picked.contains(id) },
            set: { if $0 { picked.insert(id) } else { picked.remove(id) } })
    }
}

private struct KeepAwakeAppIcon: View {
    let path: String?

    var body: some View {
        Group {
            if let path {
                Image(nsImage: IconCache.icon(forFile: path))
                    .resizable()
                    .interpolation(.high)
            } else {
                SymbolImage(name: "app.dashed", size: Theme.Size.settingsRowIcon)
            }
        }
        .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
        .accessibilityHidden(true)
    }
}

private struct KeepAwakeAppChoice: Identifiable {
    let id: String
    let name: String
    let path: String?

    init(id: String, name: String? = nil) {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        self.id = id
        path = url?.path
        self.name = name
            ?? url.map { FileManager.default.displayName(atPath: $0.path).replacing(/\.app$/, with: "") }
            ?? id
    }

    @MainActor
    static func running() -> [KeepAwakeAppChoice] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { app -> KeepAwakeAppChoice? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != own,
                  seen.insert(id).inserted
            else { return nil }
            return KeepAwakeAppChoice(id: id, name: app.localizedName)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Only meaningful once two conditions can disagree.
private struct KeepAwakeRequiresAllRow: View {
    let context: NotchcastContext
    @AppStorage private var requiresAll: Bool
    @AppStorage private var display: Bool
    @AppStorage private var power: Bool
    @AppStorage private var apps: Bool

    init(context: NotchcastContext) {
        self.context = context
        let store = context.defaults
        _requiresAll = AppStorage(wrappedValue: false, KeepAwakeSettings.Key.autoRequiresAll, store: store)
        _display = AppStorage(wrappedValue: false, KeepAwakeSettings.Key.autoDisplay, store: store)
        _power = AppStorage(wrappedValue: false, KeepAwakeSettings.Key.autoPower, store: store)
        _apps = AppStorage(wrappedValue: false, KeepAwakeSettings.Key.autoApps, store: store)
    }

    var body: some View {
        if [display, power, apps].filter(\.self).count > 1 {
            Toggle(isOn: $requiresAll) {
                SettingsRowTitle(
                    NotchcastSettingsSearch.anchor(.power),
                    LocalizedStringResource("Only when every condition is met", table: "NotchcastKeepAwake"))
                Text("Otherwise any one condition turns it on.", tableName: "NotchcastKeepAwake")
            }
            .onChange(of: requiresAll) { KeepAwakeSettingsRows.changed(context) }
        }
    }
}

/// Lid Closed needs v1's root helper; without it the switch can't change anything.
struct KeepAwakeHelperRow: View {
    let context: NotchcastContext
    @State private var installed = KeepAwakeRootPath.verify(KeepAwakeRootClient.helperPath)

    var body: some View {
        if !installed {
            LabeledContent {
                SymbolImage(name: "exclamationmark.triangle.fill", size: Theme.Size.settingsRowIcon)
                    .foregroundStyle(Theme.Colors.warning)
                    .accessibilityHidden(true)
            } label: {
                Text("Root helper not installed", tableName: "NotchcastKeepAwake")
                Text("Closing the lid still sleeps the Mac until the helper is installed.", tableName: "NotchcastKeepAwake")
            }
        }
    }
}
