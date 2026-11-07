import Foundation

/// Turns raw socket entries into grouped, display-ready rows. Pure and
/// thread-safe; runs on the background scan task, never on the main thread.
enum Presenter {

    static func snapshot(_ all: [ScanMode: [PortEntry]], now: Date = Date()) -> PortSnapshot {
        var snap = PortSnapshot()
        for mode in ScanMode.allCases {
            let entries = all[mode] ?? []
            snap.counts[mode] = entries.count
            snap.groups[mode] = mode == .established
                ? groupByApp(entries, now: now)
                : groupByProject(entries, mode: mode, now: now)
        }
        let listening = all[.listening] ?? []
        snap.exposedCount = listening.filter { $0.exposure == .exposed }.count
        snap.listeningPorts = Set(listening.map(\.port))
        return snap
    }

    // MARK: - Grouping

    private static let home = NSHomeDirectory()

    /// Listening / UDP: group by the project folder the process runs in, then
    /// Services (homebrew), Apps, System, Other.
    private static func groupByProject(_ entries: [PortEntry], mode: ScanMode, now: Date) -> [PortGroup] {
        var buckets: [String: (title: String, path: String, rank: Int, rows: [PortRow])] = [:]
        for e in entries {
            let (title, path, rank) = bucket(for: e)
            let key = "\(rank)|\(path)|\(title)"
            let row = PortRow(
                id: e.id, entry: e, port: e.port,
                name: friendlyName(e),
                sub: "\(shortCommand(e)) · PID \(e.pid)",
                uptime: uptime(e.startedAt, now: now),
                exposed: e.exposure == .exposed,
                searchText: "\(e.port) \(friendlyName(e)) \(e.label) \(e.pid)".lowercased())
            buckets[key, default: (title, path, rank, [])].rows.append(row)
        }
        return buckets
            .map { key, b in
                PortGroup(id: key, title: b.title, path: b.path,
                          rows: b.rows.sorted { $0.port < $1.port },
                          searchText: "\(b.title) \(b.path)".lowercased())
            }
            .sorted { a, b in
                let ra = rank(of: a.id), rb = rank(of: b.id)
                if ra != rb { return ra < rb }
                return (a.rows.first?.port ?? 0) < (b.rows.first?.port ?? 0)
            }
    }

    /// Established: group by the owning app, row = the peer you are talking to.
    private static func groupByApp(_ entries: [PortEntry], now: Date) -> [PortGroup] {
        var buckets: [String: (title: String, path: String, rows: [PortRow])] = [:]
        for e in entries {
            let app = appName(e.executable)
            let title = app ?? friendlyName(e)
            let path: String
            if app != nil {
                path = e.command == title ? "" : e.command
            } else {
                path = projectPath(e.cwd) ?? ""
            }
            let remote = e.remote ?? ""
            let (host, port) = splitHostPort(remote)
            let name = isLoopback(host) ? "localhost:\(port)" : host
            let row = PortRow(
                id: e.id, entry: e, port: port,
                name: name,
                sub: "\(e.address) → \(remote)",
                uptime: uptime(e.startedAt, now: now),
                exposed: false,
                searchText: "\(port) \(name) \(remote) \(e.address) \(e.pid)".lowercased())
            buckets["\(title)|\(path)", default: (title, path, [])].rows.append(row)
        }
        return buckets
            .map { key, b in
                PortGroup(id: key, title: b.title, path: b.path,
                          rows: b.rows.sorted { $0.port == $1.port ? $0.id < $1.id : $0.port < $1.port },
                          searchText: "\(b.title) \(b.path)".lowercased())
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private static func bucket(for e: PortEntry) -> (String, String, Int) {
        let exe = e.executable ?? ""
        // The folder you started it from wins: a /usr/bin/python3 dev server
        // still belongs to its project, not to "System".
        if let path = projectPath(e.cwd) {
            return (((e.cwd ?? "") as NSString).lastPathComponent, path, 0)
        }
        if exe.hasPrefix("/System/") || exe.hasPrefix("/sbin/") || exe.hasPrefix("/Library/Apple/")
            || (exe.hasPrefix("/usr/") && !exe.hasPrefix("/usr/local/")) {
            return ("System", "macOS", 3)
        }
        if exe.hasPrefix("/opt/homebrew/") || exe.hasPrefix("/usr/local/") {
            return ("Services", "homebrew", 1)
        }
        if appName(exe) != nil { return ("Apps", "Applications", 2) }
        return ("Other", "", 4)
    }

    private static func rank(of groupID: String) -> Int {
        Int(groupID.prefix { $0 != "|" }) ?? 9
    }

    /// "~/dev/web" when the folder is inside (but not equal to) home.
    private static func projectPath(_ cwd: String?) -> String? {
        guard let cwd, cwd.hasPrefix(home + "/") else { return nil }
        return "~" + cwd.dropFirst(home.count)
    }

    /// "Brave Browser" for ".../Brave Browser.app/Contents/Frameworks/...".
    private static func appName(_ exe: String?) -> String? {
        guard let exe, let range = exe.range(of: ".app/") else { return nil }
        return (String(exe[..<range.lowerBound]) as NSString).lastPathComponent
    }

    // MARK: - Names

    private static let interpreters: Set<String> = ["node", "bun", "deno", "ruby", "java", "php", "perl"]
    private static let genericScripts: Set<String> = ["index", "main", "server", "app", "cli"]
    private static let boringDirs: Set<String> = ["", ".", "dist", "src", "build", "lib", "bin", "out"]

    /// "next dev", "vite", "node api", "python http.server", else the process name.
    static func friendlyName(_ e: PortEntry) -> String {
        guard let first = e.args.first else { return e.command }
        let exe = (first as NSString).lastPathComponent
        let isPython = exe.hasPrefix("python") || exe.hasPrefix("Python")
        guard isPython || interpreters.contains(exe) else { return e.command }
        let interp = isPython ? "python" : exe

        let rest = Array(e.args.dropFirst())
        if let m = rest.firstIndex(of: "-m"), m + 1 < rest.count {
            return "\(interp) \(rest[m + 1])"
        }
        let words = rest.filter { !$0.hasPrefix("-") }
        guard let script = words.first else { return e.command }
        let sub = words.dropFirst().first.flatMap { w in
            w.count <= 16 && w.allSatisfy { $0.isLetter || $0 == ":" || $0 == "-" } ? w : nil
        }
        if let pkg = packageName(script) {
            return [pkg, sub].compactMap { $0 }.joined(separator: " ")
        }
        let path = script as NSString
        var base = (path.lastPathComponent as NSString).deletingPathExtension
        if genericScripts.contains(base) {
            let parent = (path.deletingLastPathComponent as NSString).lastPathComponent
            if !boringDirs.contains(parent) { base = parent }
        }
        return "\(interp) \(base)"
    }

    private static func packageName(_ script: String) -> String? {
        let parts = script.split(separator: "/").map(String.init)
        guard let i = parts.lastIndex(of: "node_modules"), i + 1 < parts.count else { return nil }
        let next = parts[i + 1]
        if (next == ".bin" || next.hasPrefix("@")), i + 2 < parts.count { return parts[i + 2] }
        return next
    }

    /// Command line with the working folder stripped and home shortened:
    /// "node .next/server", "python3 -m http.server 8000".
    private static func shortCommand(_ e: PortEntry) -> String {
        guard !e.args.isEmpty else { return e.command }
        let cwdPrefix = (e.cwd ?? "/") + "/"
        var out: [String] = []
        for (i, arg) in e.args.enumerated() {
            if i == 0 || arg.contains("/node_modules/") {
                // "node_modules/.bin/next" reads better as just "next".
                out.append((arg as NSString).lastPathComponent)
                continue
            }
            if cwdPrefix.count > 2, arg.hasPrefix(cwdPrefix) {
                out.append(String(arg.dropFirst(cwdPrefix.count)))
            } else if arg.hasPrefix(home) {
                out.append("~" + arg.dropFirst(home.count))
            } else {
                out.append(arg)
            }
        }
        return out.joined(separator: " ")
    }

    // MARK: - Formatting

    static func uptime(_ start: Date?, now: Date) -> String {
        guard let start else { return "" }
        let s = Int(max(0, now.timeIntervalSince(start)))
        switch s {
        case ..<60:    return "now"
        case ..<3600:  return "\(s / 60)m"
        case ..<86400: return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
        default:       return "\(s / 86400)d"
        }
    }

    private static func splitHostPort(_ address: String) -> (String, Int) {
        guard let colon = address.lastIndex(of: ":") else { return (address, 0) }
        var host = String(address[..<colon])
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        return (host, Int(address[address.index(after: colon)...]) ?? 0)
    }

    private static func isLoopback(_ host: String) -> Bool {
        host == "::1" || host.hasPrefix("127.")
    }
}
