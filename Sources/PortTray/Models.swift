import Foundation

enum ScanMode: String, CaseIterable, Identifiable, Sendable {
    case listening = "Listening"
    case established = "Established"
    case udp = "UDP"

    var id: String { rawValue }

    var proto: String { self == .udp ? "UDP" : "TCP" }

    /// Singular / plural noun for counts ("3 ports", "1 connection").
    func unit(_ n: Int) -> String {
        switch self {
        case .listening:   return n == 1 ? "port" : "ports"
        case .established: return n == 1 ? "connection" : "connections"
        case .udp:         return n == 1 ? "socket" : "sockets"
        }
    }
}

enum Exposure {
    case local     // loopback only
    case exposed   // bound to all interfaces / a routable address
}

struct PortEntry: Identifiable, Hashable, Sendable {
    var id: String { "\(pid)-\(proto)-\(port)-\(remote ?? "")" }
    let port: Int
    let pid: Int32
    let command: String
    let proto: String     // TCP / UDP
    let address: String   // local side, e.g. *:3000, 127.0.0.1:8080, [::1]:5000
    let remote: String?   // peer side for established connections
    let user: String
    var detail: String?   // full command line, e.g. "node /Users/.../server.js"
    var args: [String] = []
    var cwd: String? = nil
    var executable: String? = nil
    var startedAt: Date? = nil

    /// A readable label for the responsible process. Falls back to the
    /// command name when the full command line is unavailable.
    var label: String { detail?.isEmpty == false ? detail! : command }

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

/// One display row, with every string precomputed off the main thread so the
/// view only lays out text.
struct PortRow: Identifiable, Equatable, Sendable {
    let id: String
    let entry: PortEntry
    let port: Int
    let name: String
    let sub: String
    let uptime: String
    let exposed: Bool
    /// Lowercased haystack for the filter field.
    let searchText: String
}

struct PortGroup: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let path: String
    var rows: [PortRow]
    let searchText: String
}

/// Everything the popover shows, for all three tabs, from one kernel walk.
struct PortSnapshot: Equatable, Sendable {
    var groups: [ScanMode: [PortGroup]] = [:]
    var counts: [ScanMode: Int] = [:]
    var exposedCount = 0
    var listeningPorts: Set<Int> = []
}
