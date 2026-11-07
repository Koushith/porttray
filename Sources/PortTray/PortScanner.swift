import Foundation
import Darwin

/// Reads open sockets straight from the kernel via libproc, in-process.
///
/// This replaces shelling out to `lsof` + `ps`: no fork/exec, no text parsing,
/// and buffers / name lookups are reused between scans. Visibility is the same
/// as unprivileged lsof: processes owned by other users (e.g. root daemons)
/// are skipped because the kernel will not describe their file descriptors.
enum PortScanner {

    /// One kernel walk that fills all three tabs at once, each sorted by port.
    static func scanAll() -> [ScanMode: [PortEntry]] {
        var result: [ScanMode: [PortEntry]] = [.listening: [], .established: [], .udp: []]
        var seen = Set<String>()
        var livePids = Set<pid_t>()

        walkSockets { pid, socket in
            guard let mode = socket.mode, let entry = match(socket, mode: mode, pid: pid) else { return }
            guard seen.insert(entry.key).inserted else { return }
            livePids.insert(pid)
            result[mode, default: []].append(entry.build())
        }

        cache.forget(allExcept: livePids)
        for (mode, list) in result {
            result[mode] = list.sorted {
                $0.port == $1.port ? $0.command < $1.command : $0.port < $1.port
            }
        }
        return result
    }

    /// Single-tab scan (kept for tests / tooling).
    static func scan(mode: ScanMode) -> [PortEntry] {
        scanAll()[mode] ?? []
    }

    /// Number of listening TCP ports, used for the menu bar badge regardless of
    /// which mode the popover is currently showing. Touches no names at all.
    static func listeningCount() -> Int {
        var seen = Set<Int64>()
        walkSockets { pid, socket in
            guard socket.isTCP, socket.tcpState == TSI_S_LISTEN else { return }
            seen.insert(Int64(pid) << 16 | Int64(socket.localPort))
        }
        return seen.count
    }

    // MARK: - Kill

    /// Terminates a process. Sends SIGTERM first so it can clean up, then
    /// escalates to SIGKILL if it is still alive ~0.4s later.
    /// Returns nil on success, or a human-readable error.
    @discardableResult
    static func kill(pid: Int32) -> String? {
        if Darwin.kill(pid, SIGTERM) != 0 { return describe(errno) }
        for _ in 0..<8 {
            usleep(50_000)
            if Darwin.kill(pid, 0) != 0, errno == ESRCH { return nil }
        }
        if Darwin.kill(pid, SIGKILL) != 0, errno != ESRCH { return describe(errno) }
        return nil
    }

    private static func describe(_ code: Int32) -> String {
        switch code {
        case EPERM: return "Permission denied. That process is owned by another user."
        case ESRCH: return "That process has already exited."
        default:    return String(cString: strerror(code))
        }
    }

    // MARK: - Socket walk

    /// Reused across scans so a refresh allocates almost nothing.
    private static let buffers = Buffers()

    private final class Buffers: @unchecked Sendable {
        let lock = NSLock()
        var pids = [pid_t](repeating: 0, count: 2048)
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: 256)
    }

    private static func walkSockets(_ visit: (pid_t, Socket) -> Void) {
        let b = buffers
        b.lock.lock()
        defer { b.lock.unlock() }

        // All pids. Grow the buffer if the system has more processes than fit.
        var pidCount: Int
        repeat {
            let bytes = Int32(b.pids.count * MemoryLayout<pid_t>.stride)
            pidCount = Int(proc_listallpids(&b.pids, bytes))
            if pidCount >= b.pids.count { b.pids = .init(repeating: 0, count: pidCount * 2) }
        } while pidCount >= b.pids.count
        guard pidCount > 0 else { return }

        let fdStride = MemoryLayout<proc_fdinfo>.stride
        let infoSize = Int32(MemoryLayout<socket_fdinfo>.size)
        var info = socket_fdinfo()

        for i in 0..<pidCount {
            let pid = b.pids[i]
            guard pid > 0 else { continue }

            // Size first, so a process with thousands of fds still fits.
            let needed = Int(proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0))
            guard needed > 0 else { continue } // other user's process, or gone
            if needed / fdStride + 16 > b.fds.count {
                b.fds = .init(repeating: proc_fdinfo(), count: needed / fdStride + 64)
            }
            let got = Int(proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &b.fds,
                                       Int32(b.fds.count * fdStride)))
            guard got > 0 else { continue }

            for j in 0..<(got / fdStride) {
                let fd = b.fds[j]
                guard fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) else { continue }
                guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO,
                                     &info, infoSize) == infoSize else { continue }
                if let socket = Socket(info) { visit(pid, socket) }
            }
        }
    }

    // MARK: - Matching

    private struct Match {
        let key: String
        let build: () -> PortEntry
    }

    private static func match(_ s: Socket, mode: ScanMode, pid: pid_t) -> Match? {
        let wanted: Bool
        switch mode {
        case .listening:   wanted = s.isTCP && s.tcpState == TSI_S_LISTEN
        case .established: wanted = s.isTCP && s.tcpState == TSI_S_ESTABLISHED
        case .udp:         wanted = s.isUDP
        }
        guard wanted, s.localPort != 0 else { return nil }

        let remote = mode == .established ? s.remoteAddress : nil
        let key = "\(pid)-\(mode.proto)-\(s.localPort)-\(remote ?? "")"
        return Match(key: key) {
            let info = cache.info(for: pid)
            return PortEntry(port: Int(s.localPort), pid: pid, command: info.name,
                             proto: mode.proto, address: s.localAddress,
                             remote: remote, user: info.user, detail: info.commandLine,
                             args: info.args, cwd: info.cwd, executable: info.executable,
                             startedAt: info.startedAt)
        }
    }

    // MARK: - Process names (cached per pid)

    private static let cache = ProcessCache()

    private final class ProcessCache: @unchecked Sendable {
        struct Info {
            let name: String
            let user: String
            let args: [String]
            let cwd: String?
            let executable: String?
            let startedAt: Date?
            var commandLine: String? { args.isEmpty ? nil : args.joined(separator: " ") }
        }

        private let lock = NSLock()
        private var byPid: [pid_t: Info] = [:]
        private var users: [uid_t: String] = [:]

        func info(for pid: pid_t) -> Info {
            lock.lock(); defer { lock.unlock() }
            if let hit = byPid[pid] { return hit }
            let bsd = Self.bsdInfo(of: pid)
            let info = Info(name: Self.name(of: pid),
                            user: bsd.map { user(for: $0.pbi_uid) } ?? "",
                            args: Self.arguments(of: pid),
                            cwd: Self.workingDirectory(of: pid),
                            executable: Self.executable(of: pid),
                            startedAt: bsd.map {
                                Date(timeIntervalSince1970: TimeInterval($0.pbi_start_tvsec)
                                     + TimeInterval($0.pbi_start_tvusec) / 1_000_000)
                            })
            byPid[pid] = info
            return info
        }

        /// Drops pids that no longer own a matching socket, so the cache never
        /// grows and a reused pid gets fresh names.
        func forget(allExcept live: Set<pid_t>) {
            lock.lock(); defer { lock.unlock() }
            byPid = byPid.filter { live.contains($0.key) }
        }

        private static func name(of pid: pid_t) -> String {
            var buf = [CChar](repeating: 0, count: 256)
            return proc_name(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : "pid \(pid)"
        }

        private func user(for uid: uid_t) -> String {
            if let name = users[uid] { return name }
            let name = getpwuid(uid).map { String(cString: $0.pointee.pw_name) } ?? "\(uid)"
            users[uid] = name
            return name
        }

        private static func bsdInfo(of pid: pid_t) -> proc_bsdinfo? {
            var bsd = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size ? bsd : nil
        }

        private static func workingDirectory(of pid: pid_t) -> String? {
            var vpi = proc_vnodepathinfo()
            let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vpi, size) == size else { return nil }
            let path = withUnsafeBytes(of: &vpi.pvi_cdir.vip_path) {
                String(cString: $0.bindMemory(to: CChar.self).baseAddress!)
            }
            return path.isEmpty ? nil : path
        }

        private static func executable(of pid: pid_t) -> String? {
            var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : nil
        }

        /// Full argv via KERN_PROCARGS2, so "node" becomes
        /// ["node", "/Users/me/project/server.js"].
        private static func arguments(of pid: pid_t) -> [String] {
            var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
            var size = 0
            guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
            var buf = [UInt8](repeating: 0, count: size)
            guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return [] }

            let argc = buf.withUnsafeBytes { $0.load(as: Int32.self) }
            var i = MemoryLayout<Int32>.size
            while i < size, buf[i] != 0 { i += 1 } // exec path
            while i < size, buf[i] == 0 { i += 1 } // padding

            var args: [String] = []
            while args.count < argc, i < size {
                let start = i
                while i < size, buf[i] != 0 { i += 1 }
                args.append(String(decoding: buf[start..<i], as: UTF8.self))
                i += 1
            }
            // Some processes rewrite argv in place and pad it with spaces.
            return args
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }
}

// MARK: - Kernel socket record

private struct Socket {
    let isTCP: Bool
    let isUDP: Bool
    let tcpState: Int32
    let localPort: UInt16
    let localAddress: String   // "*:3000", "127.0.0.1:8080", "[::1]:5000"
    let remoteAddress: String?

    /// Which popover tab this socket belongs to, if any.
    var mode: ScanMode? {
        if isUDP { return .udp }
        switch tcpState {
        case TSI_S_LISTEN:      return .listening
        case TSI_S_ESTABLISHED: return .established
        default:                return nil
        }
    }

    init?(_ info: socket_fdinfo) {
        let psi = info.psi
        let ini: in_sockinfo
        switch psi.soi_kind {
        case Int32(SOCKINFO_TCP):
            ini = psi.soi_proto.pri_tcp.tcpsi_ini
            isTCP = true
            isUDP = false
            tcpState = psi.soi_proto.pri_tcp.tcpsi_state
        case Int32(SOCKINFO_IN):
            guard psi.soi_protocol == IPPROTO_UDP else { return nil }
            ini = psi.soi_proto.pri_in
            isTCP = false
            isUDP = true
            tcpState = -1
        default:
            return nil
        }

        let v6 = ini.insi_vflag & UInt8(INI_IPV6) != 0
        localPort = UInt16(bigEndian: UInt16(truncatingIfNeeded: ini.insi_lport))
        localAddress = Socket.format(v4: ini.insi_laddr.ina_46.i46a_addr4, v6: ini.insi_laddr.ina_6, isV6: v6, port: localPort)

        let fport = UInt16(bigEndian: UInt16(truncatingIfNeeded: ini.insi_fport))
        remoteAddress = fport == 0 ? nil : Socket.format(v4: ini.insi_faddr.ina_46.i46a_addr4, v6: ini.insi_faddr.ina_6, isV6: v6, port: fport)
    }

    private static func format(v4: in_addr, v6: in6_addr, isV6: Bool, port: UInt16) -> String {
        var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        if isV6 {
            var a6 = v6
            if a6 == in6addr_any { return "*:\(port)" }
            // IPv4-mapped (::ffff:a.b.c.d) prints as plain IPv4, like lsof.
            if a6.__u6_addr.__u6_addr32.0 == 0, a6.__u6_addr.__u6_addr32.1 == 0,
               a6.__u6_addr.__u6_addr32.2 == UInt32(0xffff).bigEndian {
                var a4 = in_addr(s_addr: a6.__u6_addr.__u6_addr32.3)
                inet_ntop(AF_INET, &a4, &text, socklen_t(text.count))
                return "\(String(cString: text)):\(port)"
            }
            inet_ntop(AF_INET6, &a6, &text, socklen_t(text.count))
            return "[\(String(cString: text))]:\(port)"
        }
        var a4 = v4
        if a4.s_addr == 0 { return "*:\(port)" }
        inet_ntop(AF_INET, &a4, &text, socklen_t(text.count))
        return "\(String(cString: text)):\(port)"
    }
}

private func == (a: in6_addr, b: in6_addr) -> Bool {
    a.__u6_addr.__u6_addr32 == b.__u6_addr.__u6_addr32
}
