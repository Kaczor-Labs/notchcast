import Foundation
import Observation

/// The row's question: Turn off applies; Cancel or a dismissal without an answer turns the switch off.
@MainActor
@Observable
final class IPhoneBackupConfirmation {
    private(set) var isPresented = false
    @ObservationIgnored private let store: IPhoneBackupStore
    @ObservationIgnored private var isAnswered = false

    init(store: IPhoneBackupStore) {
        self.store = store
    }

    func appear() {
        store.refresh()
        guard !store.isApplied else { return }
        isAnswered = false
        isPresented = true
    }

    func accept() {
        answer()
        store.apply()
    }

    func cancel() {
        answer()
        store.decline()
    }

    /// SwiftUI may clear the binding before a button's action runs, so a dismissal waits one turn.
    func setPresented(_ presented: Bool) {
        guard !presented, isPresented else { return }
        isPresented = false
        Task { @MainActor [weak self] in
            guard let self, !isAnswered, !isPresented else { return }
            cancel()
        }
    }

    private func answer() {
        isAnswered = true
        isPresented = false
    }
}
