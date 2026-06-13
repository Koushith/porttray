import Foundation

enum ScanMode: String, CaseIterable, Identifiable {
    case listening = "Listening"
    case established = "Established"
    case udp = "UDP"

    var id: String { rawValue }

    /// Protocol/state selectors passed to lsof.
    var lsofArgs: [String] {
        switch self {
        case .listening:   return ["-iTCP", "-sTCP:LISTEN"]
        case .established: return ["-iTCP", "-sTCP:ESTABLISHED"]
        case .udp:         return ["-iUDP"]
        }
    }

    var proto: String { self == .udp ? "UDP" : "TCP" }
}

enum Exposure {
    case local     // loopback only
    case exposed   // bound to all interfaces / a routable address
}

struct PortEntry: Identifiable, Hashable {
    var id: String { "\(pid)-\(proto)-\(port)-\(remote ?? "")" }
    let port: Int
    let pid: Int32
    let command: String
    let proto: String     // TCP / UDP
    let address: String   // local side, e.g. *:3000, 127.0.0.1:8080, [::1]:5000
    let remote: String?   // peer side for established connections
    let user: String

    var isLoopbackOnly: Bool {
        address.hasPrefix("127.0.0.1:") || address.hasPrefix("[::1]:")
    }

    var exposure: Exposure { isLoopbackOnly ? .local : .exposed }

    /// A localhost web port we can open in a browser.
    var browserURL: URL? {
        guard proto == "TCP",
              address.hasPrefix("127.0.0.1:") || address.hasPrefix("*:")
                || address.hasPrefix("0.0.0.0:") || address.hasPrefix("[::1]:")
                || address.hasPrefix("[::]:")
        else { return nil }
        return URL(string: "http://localhost:\(port)")
    }
}
