import Foundation

enum PortScanner {

    /// Scans sockets for the given mode and returns them sorted by port number.
    static func scan(mode: ScanMode) -> [PortEntry] {
        guard let output = runLsof(mode: mode) else { return [] }
        return parse(output, mode: mode)
    }

    private static func runLsof(mode: ScanMode) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // +c0 -> full command names, -nP -> numeric (no DNS/port lookups),
        // -FpcnL -> machine-readable: p=pid, c=command, n=name, L=login.
        task.arguments = ["+c0", "-nP"] + mode.lsofArgs + ["-FpcnL"]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    private static func parse(_ output: String, mode: ScanMode) -> [PortEntry] {
        var entries: [PortEntry] = []
        var pid: Int32 = 0
        var command = ""
        var user = ""

        for raw in output.split(separator: "\n") {
            guard let tag = raw.first else { continue }
            let value = String(raw.dropFirst())
            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "c": command = value
            case "L": user = value
            case "n":
                // value: "*:3000" / "127.0.0.1:8080" / "[::1]:5000"
                // established: "127.0.0.1:54321->127.0.0.1:3000"
                let parts = value.components(separatedBy: "->")
                let local = parts[0]
                let remote = parts.count > 1 ? parts[1] : nil
                if let port = port(from: local) {
                    entries.append(
                        PortEntry(port: port, pid: pid, command: command,
                                  proto: mode.proto, address: local,
                                  remote: remote, user: user)
                    )
                }
            default:
                break
            }
        }

        var seen = Set<String>()
        return entries
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.port == $1.port ? $0.command < $1.command : $0.port < $1.port }
    }

    private static func port(from address: String) -> Int? {
        guard let colon = address.lastIndex(of: ":") else { return nil }
        return Int(address[address.index(after: colon)...])
    }

    /// SIGTERM by default, SIGKILL when force is true.
    /// Returns nil on success, or a human-readable error.
    @discardableResult
    static func kill(pid: Int32, force: Bool) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/kill")
        task.arguments = [force ? "-9" : "-15", "\(pid)"]
        let err = Pipe()
        task.standardError = err
        do { try task.run() } catch { return error.localizedDescription }
        task.waitUntilExit()
        if task.terminationStatus == 0 { return nil }
        let data = err.fileHandleForReading.readDataToEndOfFile()
        let msg = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if msg.contains("Operation not permitted") {
            return "Permission denied — that process is owned by another user."
        }
        return msg.isEmpty ? "kill exited with code \(task.terminationStatus)" : msg
    }
}
