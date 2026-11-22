import Foundation

struct NoNotchcastSettingsPayload: Codable, Sendable {}

protocol NotchcastSettingsEndpoint: NotchcastAddon {
    associatedtype Status: Codable & Sendable = NoNotchcastSettingsPayload
    associatedtype Action: Codable & Sendable = NoNotchcastSettingsPayload
    associatedtype Request: Codable & Sendable = NoNotchcastSettingsPayload
    associatedtype Reply: Codable & Sendable = NoNotchcastSettingsPayload

    static var settingsID: String { get }
    static func settingsStatus(_ context: NotchcastContext) -> Status?
    static func perform(_ action: Action, context: NotchcastContext)
    static func answer(_ request: Request, context: NotchcastContext) async throws -> Reply
}

extension NotchcastSettingsEndpoint {
    static func encodedStatus(_ context: NotchcastContext) -> Data? {
        settingsStatus(context).flatMap { try? NotchcastSettingsMessage.encode($0) }
    }

    static func performSettingsAction(_ payload: Data, context: NotchcastContext) {
        guard let action = try? JSONDecoder().decode(Action.self, from: payload) else { return }
        perform(action, context: context)
    }

    static func answerSettingsRequest(_ payload: Data, context: NotchcastContext) async throws -> Data {
        let request = try JSONDecoder().decode(Request.self, from: payload)
        let reply = try await answer(request, context: context)
        return try NotchcastSettingsMessage.encode(reply)
    }
}

extension NotchcastSettingsEndpoint where Status == NoNotchcastSettingsPayload {
    static func settingsStatus(_ context: NotchcastContext) -> NoNotchcastSettingsPayload? { nil }
}

extension NotchcastSettingsEndpoint where Action == NoNotchcastSettingsPayload {
    static func perform(_ action: NoNotchcastSettingsPayload, context: NotchcastContext) {}
}

extension NotchcastSettingsEndpoint where Request == NoNotchcastSettingsPayload, Reply == NoNotchcastSettingsPayload {
    static func answer(
        _ request: NoNotchcastSettingsPayload, context: NotchcastContext
    ) async throws -> NoNotchcastSettingsPayload {
        throw CocoaError(.coderReadCorrupt)
    }
}

extension MainAppLink {
    func notchcastStatus<Endpoint: NotchcastSettingsEndpoint>(for endpoint: Endpoint.Type) -> Endpoint.Status? {
        guard let data = status.notchcast.addons[endpoint.settingsID] else { return nil }
        return try? JSONDecoder().decode(Endpoint.Status.self, from: data)
    }

    func sendNotchcast<Endpoint: NotchcastSettingsEndpoint>(_ action: Endpoint.Action, to endpoint: Endpoint.Type) {
        guard let payload = try? NotchcastSettingsMessage.encode(action) else { return }
        send(.notchcast(.addon(.init(id: endpoint.settingsID, payload: payload))))
    }

    func callNotchcast<Endpoint: NotchcastSettingsEndpoint>(
        _ request: Endpoint.Request, to endpoint: Endpoint.Type
    ) async throws -> Endpoint.Reply {
        let payload = try NotchcastSettingsMessage.encode(request)
        let data = try await callNotchcast(.init(id: endpoint.settingsID, payload: payload))
        return try JSONDecoder().decode(Endpoint.Reply.self, from: data)
    }
}
