import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Renders the real PortListView with demo data to produce the README
/// screenshots and the kill-flow GIF. No screen recording, no permissions,
/// and none of your own processes end up in the images.
/// Invoked with: PortTray --shots <output-dir>
@MainActor
enum ScreenshotMaker {
    private static var window: NSWindow?

    static func run(outputDir: String) {
        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let full = Presenter.snapshot(demo, now: now)
        let row3000 = full.groups[.listening]!.flatMap(\.rows).first { $0.port == 3000 }!
        let row8080 = full.groups[.listening]!.flatMap(\.rows).first { $0.port == 8080 }!

        // Stills.
        save(shot(full, .aqua, hover: row8080.id), "\(outputDir)/listening.png")
        save(shot(full, .aqua, confirm: row3000.id), "\(outputDir)/kill-confirm.png")
        save(shot(full, .aqua, query: "4000"), "\(outputDir)/port-free.png")
        save(shot(full, .darkAqua, mode: .established), "\(outputDir)/established-dark.png")

        // Kill flow: browse -> hover -> confirm -> gone + toast.
        var after = demo
        after[.listening]?.removeAll { $0.port == 3000 }
        let afterSnap = Presenter.snapshot(after, now: now)
        let toastStore = PortStore(preview: afterSnap)
        toastStore.showToast("next dev stopped · :3000 is free")
        let frames = [
            shot(full, .aqua),
            shot(full, .aqua, hover: row3000.id),
            shot(full, .aqua, confirm: row3000.id),
            shot(afterSnap, .aqua, store: toastStore),
        ].compactMap { $0 }
        saveGIF(frames, durations: [1.4, 1.2, 1.8, 2.4], to: "\(outputDir)/demo.gif")

        print("Wrote screenshots to \(outputDir)")
    }

    // MARK: - Rendering

    private static func shot(_ snap: PortSnapshot, _ look: NSAppearance.Name,
                             mode: ScanMode = .listening, query: String = "",
                             confirm: String? = nil, hover: String? = nil,
                             store: PortStore? = nil) -> CGImage? {
        let store = store ?? PortStore(preview: snap)
        let view = ShotFrame(count: snap.counts[.listening] ?? 0) {
            PortListView(store: store, loginItem: LoginItem(), mode: mode,
                         query: query, confirmID: confirm, previewHoverID: hover)
        }
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize
        let win = window ?? NSWindow(contentRect: .zero, styleMask: .borderless,
                                     backing: .buffered, defer: false)
        window = win
        win.appearance = NSAppearance(named: look)
        win.setFrame(NSRect(origin: NSPoint(x: -5000, y: -5000), size: host.fittingSize), display: false)
        win.contentView = host
        win.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.cgImage
    }

    private static func save(_ image: CGImage?, _ path: String) {
        guard let image,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private static func saveGIF(_ frames: [CGImage], durations: [Double], to path: String) {
        guard !frames.isEmpty,
              let dest = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: path) as CFURL, UTType.gif.identifier as CFString,
                frames.count, nil)
        else { return }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary:
            [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (i, frame) in frames.enumerated() {
            CGImageDestinationAddImage(dest, frame, [kCGImagePropertyGIFDictionary:
                [kCGImagePropertyGIFUnclampedDelayTime: durations[i]]] as CFDictionary)
        }
        CGImageDestinationFinalize(dest)
    }

    // MARK: - Demo data

    private static let now = Date()
    private static let home = NSHomeDirectory()

    private static func e(_ port: Int, _ pid: Int32, _ command: String, _ address: String,
                          _ args: [String], cwd: String, exe: String, up: TimeInterval,
                          proto: String = "TCP", remote: String? = nil) -> PortEntry {
        PortEntry(port: port, pid: pid, command: command, proto: proto, address: address,
                  remote: remote, user: "me", detail: args.joined(separator: " "),
                  args: args, cwd: cwd, executable: exe, startedAt: now.addingTimeInterval(-up))
    }

    private static let h: TimeInterval = 3600, m: TimeInterval = 60, d: TimeInterval = 86400
    private static let node = "/opt/homebrew/bin/node"

    private static var demo: [ScanMode: [PortEntry]] {
        let web = home + "/dev/web", api = home + "/dev/api"
        let chrome = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
        let slack = "/Applications/Slack.app/Contents/Frameworks/Slack Helper.app/Contents/MacOS/Slack Helper"
        return [
            .listening: [
                e(3000, 4821, "node", "*:3000", ["node", web + "/node_modules/.bin/next", "dev"],
                  cwd: web, exe: node, up: 2 * h + 14 * m),
                e(5173, 4977, "node", "127.0.0.1:5173", ["node", web + "/node_modules/.bin/vite"],
                  cwd: web, exe: node, up: 41 * m),
                e(8080, 5510, "node", "*:8080", ["node", "api/index.js"],
                  cwd: api, exe: node, up: 2 * h + 10 * m),
                e(8081, 5531, "node", "127.0.0.1:8081", ["node", "api/worker.js"],
                  cwd: api, exe: node, up: 2 * h + 10 * m),
                e(5432, 1380, "postgres", "127.0.0.1:5432",
                  ["/opt/homebrew/opt/postgresql@16/bin/postgres", "-D", "/opt/homebrew/var/postgresql@16"],
                  cwd: "/opt/homebrew/var/postgresql@16", exe: "/opt/homebrew/opt/postgresql@16/bin/postgres", up: 3 * d),
                e(6379, 1402, "redis-server", "127.0.0.1:6379",
                  ["/opt/homebrew/opt/redis/bin/redis-server", "127.0.0.1:6379"],
                  cwd: "/", exe: "/opt/homebrew/opt/redis/bin/redis-server", up: 3 * d),
                e(8000, 6233, "Python", "*:8000", ["python3", "-m", "http.server", "8000"],
                  cwd: home + "/Downloads", exe: "/usr/bin/python3", up: 6 * m),
            ],
            .established: [
                e(52811, 5510, "node", "127.0.0.1:52811", ["node", "api/index.js"],
                  cwd: api, exe: node, up: 2 * h + 10 * m, remote: "127.0.0.1:5432"),
                e(52814, 5510, "node", "127.0.0.1:52814", ["node", "api/index.js"],
                  cwd: api, exe: node, up: 2 * h + 10 * m, remote: "127.0.0.1:6379"),
                e(51822, 7120, "Google Chrome Helper", "192.168.1.24:51822", [],
                  cwd: "/", exe: chrome, up: 12 * m, remote: "140.82.112.4:443"),
                e(51907, 7120, "Google Chrome Helper", "192.168.1.24:51907", [],
                  cwd: "/", exe: chrome, up: 4 * m, remote: "160.79.104.10:443"),
                e(51960, 7120, "Google Chrome Helper", "[::1]:51960", [],
                  cwd: "/", exe: chrome, up: 1 * m, remote: "[::1]:3000"),
                e(50211, 7730, "Slack Helper", "192.168.1.24:50211", [],
                  cwd: "/", exe: slack, up: 1 * h + 2 * m, remote: "3.110.42.17:443"),
            ],
            .udp: [
                e(8125, 5602, "node", "127.0.0.1:8125", ["node", "statsd-mock.js"],
                  cwd: api, exe: node, up: 2 * h + 8 * m, proto: "UDP"),
            ],
        ]
    }
}

/// Frames the popover like it sits under the menu bar: a slice of menu bar
/// with the tray item, then the panel with its rounded corners and shadow.
private struct ShotFrame<Content: View>: View {
    let count: Int
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 5) {
                Image(nsImage: MenuBarIcon.image)
                    .renderingMode(.template)
                Text(verbatim: "\(count)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(dark ? Color.white : Color.black.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background((dark ? Color.white.opacity(0.18) : Color.black.opacity(0.10)),
                        in: RoundedRectangle(cornerRadius: 5))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 24)
            .frame(height: 28)
            .background(dark ? Color(white: 0.15).opacity(0.9) : Color.white.opacity(0.75))

            content
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(dark ? Color.white.opacity(0.11) : Color.black.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(dark ? 0.55 : 0.16), radius: 24, y: 14)
                .padding(EdgeInsets(top: 0, leading: 28, bottom: 44, trailing: 28))
        }
        .frame(width: 456)
        .background(dark ? Color(red: 0.08, green: 0.08, blue: 0.09)
                         : Color(red: 0.84, green: 0.85, blue: 0.87))
    }
}
