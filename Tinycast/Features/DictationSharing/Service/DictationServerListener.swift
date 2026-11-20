import Network

/// The endpoint's listener, bound to IPv4 loopback so nothing off this Mac can connect.
enum DictationServerListener {
    static func make(port: NWEndpoint.Port) throws -> NetworkListener<TCP> {
        try NetworkListener(
            using: .parameters { TCP() }
                .localEndpoint(.hostPort(host: .ipv4(.loopback), port: port)))
    }
}
