import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Renders the real PortListView offscreen with curated data to produce the
/// README screenshots and the kill-flow animation. No screen recording, no
/// permissions. Invoked with: PortTray --shots <output-dir>
@MainActor
enum ScreenshotMaker {

    static func run(outputDir: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        // Still 1: listening ports (the default view).
        savePNG(ShotView(entries: listening, selected: .listening),
                to: outputDir + "/listening.png")

        // Still 2: established connections, showing the remote peer.
        savePNG(ShotView(entries: established, selected: .established),
                to: outputDir + "/established.png")

        // Animation: kill two ports, list shrinks one row at a time. All frames
        // are padded to the tallest height so the GIF canvas stays fixed (a GIF
        // sizes to its first frame; shorter frames would otherwise leave residue).
        let frames = [listening, killing(3000), without(3000),
                      killing2(8080, from: without(3000)), without(3000, 8080)]
        let fullHeight = cgImage(of: ShotView(entries: listening, selected: .listening))
            .map { Double($0.height) / 2.0 } ?? 800
        let cgFrames = frames.compactMap { entries in
            cgImage(of: ShotView(entries: entries, selected: .listening)
                .frame(width: 380, height: fullHeight, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor)))
        }
        saveGIF(cgFrames,
                durations: [1.6, 0.6, 1.0, 0.6, 1.8],
                to: outputDir + "/demo.gif")

        print("Wrote screenshots to \(outputDir)")
    }

    // MARK: - Rendering

    private static func cgImage(of view: some View) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.cgImage
    }

    private static func savePNG(_ view: some View, to path: String) {
        guard let cg = cgImage(of: view) else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private static func saveGIF(_ frames: [CGImage], durations: [Double], to path: String) {
        guard !frames.isEmpty,
              let dest = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: path) as CFURL,
                UTType.gif.identifier as CFString,
                frames.count, nil)
        else { return }

        let fileProps = [kCGImagePropertyGIFDictionary:
                            [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        CGImageDestinationSetProperties(dest, fileProps)

        for (i, frame) in frames.enumerated() {
            let delay = i < durations.count ? durations[i] : 1.0
            let frameProps = [kCGImagePropertyGIFDictionary:
                                [kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary
            CGImageDestinationAddImage(dest, frame, frameProps)
        }
        CGImageDestinationFinalize(dest)
    }

    // MARK: - Sample data

    private static func entry(_ port: Int, _ pid: Int32, _ command: String,
                              _ address: String, _ detail: String,
                              proto: String = "TCP", remote: String? = nil) -> PortEntry {
        PortEntry(port: port, pid: pid, command: command, proto: proto,
                  address: address, remote: remote, user: "koushith", detail: detail)
    }

    private static let listening: [PortEntry] = [
        entry(3000, 4821, "node", "*:3000", "node /Users/koushith/dev/web/.next/server"),
        entry(5173, 4977, "node", "127.0.0.1:5173", "node node_modules/.bin/vite"),
        entry(5432, 1380, "postgres", "127.0.0.1:5432", "postgres -D /opt/homebrew/var/postgresql@16"),
        entry(6379, 1402, "redis-server", "127.0.0.1:6379", "redis-server 127.0.0.1:6379"),
        entry(8080, 5510, "node", "*:8080", "node api/index.js"),
        entry(8000, 6233, "Python", "127.0.0.1:8000", "Python -m http.server 8000"),
    ]

    private static let established: [PortEntry] = [
        entry(53344, 7720, "node", "127.0.0.1:53344",
              "node api/index.js", remote: "127.0.0.1:5432"),
        entry(51002, 9120, "Spotify", "192.168.1.20:51002",
              "Spotify", remote: "35.186.224.25:443"),
        entry(55210, 9330, "Arc", "192.168.1.20:55210",
              "Arc Helper", remote: "140.82.113.25:443"),
    ]

    /// Listening set with the named ports removed (simulates a kill).
    private static func without(_ ports: Int...) -> [PortEntry] {
        listening.filter { !ports.contains($0.port) }
    }

    /// The given port shown mid-kill (dimmed via a "stopping…" marker).
    private static func killing(_ port: Int) -> [PortEntry] {
        killing2(port, from: listening)
    }

    private static func killing2(_ port: Int, from list: [PortEntry]) -> [PortEntry] {
        list.map {
            guard $0.port == port else { return $0 }
            return entry($0.port, $0.pid, $0.command, $0.address,
                         "stopping…", proto: $0.proto, remote: $0.remote)
        }
    }
}
