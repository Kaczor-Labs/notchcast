/// Every add-on, one line each; deleting an add-on is its folder plus its line here.
@MainActor
enum NotchcastRegistry {
    static let addons: [any NotchcastAddon.Type] = [
        HideCommandMAddon.self,
        ShowDesktopAddon.self,
    ]
}
