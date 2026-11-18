// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/SystemToolsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/KillProcessSession.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SystemToolsPicking.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SystemToolsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SystemToolsModule+Addresses.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SystemToolsSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SudoTouchIDStore.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift Tests/nc-SystemTools-fixture.swift

import AppKit
import Foundation

// On fakes: no interface is read, no request is sent, no keychain is asked.
@main
@MainActor
enum SystemToolsNetworkTests {
    static var failures = 0
    static var checks = 0

    static func check(_ name: String, _ value: Bool) {
        checks += 1
        if !value { failures += 1; print("FAIL \(name)") }
    }

    static func main() async {
        await localAddress()
        await publicAddress()
        await wifiPassword()
        await currentWiFiPassword()
        await switchingOffDropsALookup()
        print("\(checks) system tools network checks; \(failures) failures")
        if failures > 0 { exit(1) }
        print("PASSED")
    }

    static func localAddress() async {
        let rig = Rig()
        defer { rig.finish() }
        let module = await rig.module()
        fake.addresses = []
        module.copyLocalAddress()
        check("no address reports a failure", rig.presenter.posts.last?.isFailure == true)
        check("no address copies nothing", fake.copies.isEmpty)
        fake.addresses = [LocalAddress(ip: "10.0.0.2", connection: nil), LocalAddress(ip: "192.168.1.5", connection: "Wi-Fi")]
        module.copyLocalAddress()
        check("every address is copied, one per line, in plain",
              fake.copies.last.map { $0.text == "10.0.0.2\n192.168.1.5" && !$0.concealed } == true)
        let shown = rig.presenter.posts.last
        check("the island names the connection (\(shown?.text ?? ""))",
              shown?.text.contains("192.168.1.5 (Wi-Fi)") == true && shown?.isFailure == false)
        fake.copies = []
    }

    static func publicAddress() async {
        let rig = Rig()
        defer { rig.finish() }
        let module = await rig.module()
        fake.publicReply = Data("203.0.113.7\n".utf8)
        module.copyPublicAddress()
        check("the lookup shows progress first", rig.presenter.posts.last?.progress != nil)
        check("the reply is copied", await until { fake.copies.last?.text == "203.0.113.7" })
        check("the island shows it", rig.presenter.posts.last?.text.contains("203.0.113.7") == true)
        fake.copies = []
        fake.publicReply = Data("<html>blocked</html>".utf8)
        module.copyPublicAddress()
        check("a reply that is no address fails", await until { rig.presenter.posts.last?.isFailure == true })
        check("a reply that is no address is never copied", fake.copies.isEmpty)
        fake.publicReply = nil
        module.copyPublicAddress()
        check("no connection fails", await until { rig.presenter.posts.last?.isFailure == true })
        fake.publicReply = nil
    }

    static func wifiPassword() async {
        let rig = Rig()
        defer { rig.finish() }
        let module = await rig.module()
        fake.savedNetworks = []
        module.copyWiFiPassword()
        check("no saved network reports a failure", await until { rig.presenter.posts.last?.isFailure == true })
        check("no saved network opens no picker", fake.pickers == 0)

        fake.savedNetworks = ["Home", "Office", "Cafe"]
        fake.passwords = ["Home": "hunter2", "Office": "fail"]
        module.copyWiFiPassword()
        guard await until({ fake.pickers == 1 }), let session = fake.sessions.last as? WiFiNetworkSession else {
            return check("saved networks open the picker", false)
        }
        check("the picker lists the saved networks in order", session.pickerRows.map(\.title) == ["Home", "Office", "Cafe"])
        check("Location off never asks", fake.locationAsks == 0)
        check("the picker says Location is off (\(session.header))", session.header.contains("Location"))
        session.query = "OFF"
        check("typing filters the networks", session.networks == ["Office"])
        session.activate(0, option: false)
        check("a refused read fails", await until { rig.presenter.posts.last?.isFailure == true })
        check("a refused read copies nothing", fake.copies.isEmpty)
        session.query = ""
        session.activate(2, option: false)
        check("a network with no saved password says so",
              await until { rig.presenter.posts.last?.text.contains("Cafe") == true })
        session.activate(0, option: false)
        check("the chosen network's password is read", await until { fake.passwordReads.last == "Home" })
        check("the password is copied concealed",
              await until { fake.copies.last.map { $0.text == "hunter2" && $0.concealed } == true })
        let shown = rig.presenter.posts.last
        check("the island shows it long enough to read",
              shown?.text.contains("hunter2") == true && shown?.seconds == SystemToolsModule.resultSeconds)
        fake.copies = []
        fake.passwordReads = []
        fake.passwords = [:]
        fake.savedNetworks = []
    }

    static func currentWiFiPassword() async {
        let rig = Rig()
        defer { rig.finish() }
        let module = await rig.module()
        fake.savedNetworks = ["Home", "Office"]
        fake.passwords = ["Home": "hunter2", "Office": "s3cret"]
        fake.currentNetwork = "Office"

        fake.locationAccess = .allowed
        module.copyWiFiPassword()
        check("with Location on the current network's password is copied concealed",
              await until { fake.copies.last.map { $0.text == "s3cret" && $0.concealed } == true })
        check("the current network needs no picker and no prompt", fake.pickers == 0 && fake.locationAsks == 0)
        check("only the current network is read", fake.passwordReads == ["Office"])
        check("the island names the network", rig.presenter.posts.last?.text.contains("Office") == true)

        fake.copies = []
        fake.locationAccess = .undecided
        fake.locationAnswer = .allowed
        module.copyWiFiPassword()
        check("an undecided Location asks, then copies", await until { fake.copies.last?.text == "s3cret" })
        check("it asks once and opens no picker", fake.locationAsks == 1 && fake.pickers == 0)

        fake.copies = []
        fake.locationAccess = .undecided
        fake.locationAnswer = .off
        module.copyWiFiPassword()
        check("a refused Location opens the picker", await until { fake.pickers == 1 })
        check("a refused Location was asked and copies nothing", fake.locationAsks == 2 && fake.copies.isEmpty)
        check("the picker says why", (fake.sessions.last as? WiFiNetworkSession)?.header.contains("Location") == true)

        fake.locationAccess = .allowed
        fake.currentNetwork = nil
        module.copyWiFiPassword()
        check("off Wi-Fi opens the picker", await until { fake.pickers == 2 })
        check("off Wi-Fi blames nothing on Location",
              (fake.sessions.last as? WiFiNetworkSession)?.header.contains("Location") == false)

        fake.locationAccess = .off
        fake.locationAnswer = .off
        fake.locationAsks = 0
        fake.pickers = 0
        fake.sessions = []
        fake.passwordReads = []
        fake.passwords = [:]
        fake.savedNetworks = []
    }

    static func switchingOffDropsALookup() async {
        let rig = Rig()
        defer { rig.finish() }
        let module = await rig.module()
        fake.publicReply = Data("203.0.113.7".utf8)
        module.copyPublicAddress()
        rig.controller.preferences.set(SystemToolsAddon.switchID, on: false)
        _ = await until { false }
        check("a lookup the switch ended copies nothing", fake.copies.isEmpty)
        fake.publicReply = nil
    }
}
