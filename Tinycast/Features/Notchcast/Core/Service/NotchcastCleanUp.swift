@MainActor
final class NotchcastCleanUp {
    private var id: String?
    private(set) var title: String?
    private var run: ((String) -> Void)?
    var onChange: (() -> Void)?

    func setAction(id: String?, title: String?, run: @escaping (String) -> Void) {
        guard id != self.id || title != self.title else { return }
        self.id = id
        self.title = title
        self.run = id == nil ? nil : run
        onChange?()
    }

    func open() {
        guard let id else { return }
        run?(id)
    }
}

extension NotchcastContext {
    var cleanUp: NotchcastCleanUp { services.cleanUp }
}
