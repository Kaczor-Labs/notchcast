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
