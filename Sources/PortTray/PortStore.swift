import SwiftUI

@MainActor
final class PortStore: ObservableObject {
    @Published private(set) var entries: [PortEntry] = []
    @Published private(set) var badgeCount: Int = 0
    @Published var statusMessage: String?
    @Published var mode: ScanMode = .listening {
        didSet { refresh() }
    }

    /// Refreshes the visible list for the current mode.
    func refresh() {
        entries = PortScanner.scan(mode: mode)
        refreshBadge()
    }

    /// Refreshes only the menu bar badge (always the listening count, so the
    /// tray width does not jump when you switch modes in the popover).
    func refreshBadge() {
        badgeCount = PortScanner.listeningCount()
    }

    func kill(_ entry: PortEntry) {
        statusMessage = PortScanner.kill(pid: entry.pid)
        // Give the OS a moment to reap the process, then re-scan.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }
}
