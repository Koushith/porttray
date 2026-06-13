import Foundation

enum PortScanner {

    /// Scans sockets for the given mode and returns them sorted by port number.
    static func scan(mode: ScanMode) -> [PortEntry] {
        guard let output = runLsof(mode: mode) else { return [] }
        var entries = parse(output, mode: mode)
        let cmdlines = commandLines(for: Set(entries.map { $0.pid }))
        for i in entries.indices {
            entries[i].detail = cmdlines[entries[i].pid]
        }
        return entries
    }

    /// Number of listening TCP ports, used for the menu bar badge regardless of
    /// which mode the popover is currently showing.
    static func listeningCount() -> Int {
        guard let output = runLsof(mode: .listening) else { return 0 }
        return parse(output, mode: .listening).count
    }

    /// Maps PIDs to their full command line via `ps`, so "node" becomes
    /// "node /Users/me/project/server.js" and you can tell what is responsible.
    private static func commandLines(for pids: Set<Int32>) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axww", "-o", "pid=,command="]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = Pipe()
        do { try task.run() } catch { return [:] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [:] }

        var result: [Int32: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.drop { $0 == " " }
            guard let space = trimmed.firstIndex(of: " ") else { continue }
            guard let pid = Int32(trimmed[..<space]), pids.contains(pid) else { continue }
            let command = trimmed[trimmed.index(after: space)...]
                .trimmingCharacters(in: .whitespaces)
            result[pid] = command
        }
        return result
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

    /// Terminates a process. Sends SIGTERM first so it can clean up, then
    /// escalates to SIGKILL if it is still alive a moment later.
    /// Returns nil on success, or a human-readable error.
    @discardableResult
    static func kill(pid: Int32) -> String? {
        if let error = signal("-15", pid) { return error }
        usleep(400_000) // 0.4s grace period
        if isAlive(pid) {
            if let error = signal("-9", pid) { return error }
        }
        return nil
    }

    private static func signal(_ flag: String, _ pid: Int32) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/kill")
        task.arguments = [flag, "\(pid)"]
        let err = Pipe()
        task.standardError = err
        do { try task.run() } catch { return error.localizedDescription }
        task.waitUntilExit()
        if task.terminationStatus == 0 { return nil }
        let data = err.fileHandleForReading.readDataToEndOfFile()
        let msg = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if msg.contains("Operation not permitted") {
            return "Permission denied. That process is owned by another user."
        }
        return msg.isEmpty ? "kill exited with code \(task.terminationStatus)" : msg
    }

    private static func isAlive(_ pid: Int32) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/kill")
        task.arguments = ["-0", "\(pid)"]
        task.standardError = Pipe()
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}
