import SwiftUI

@MainActor
final class PortStore: ObservableObject {
    @Published private(set) var entries: [PortEntry] = []
    @Published var statusMessage: String?
    @Published var mode: ScanMode = .listening {
        didSet { refresh() }
    }

    func refresh() {
        entries = PortScanner.scan(mode: mode)
    }

    func kill(_ entry: PortEntry, force: Bool) {
        if let error = PortScanner.kill(pid: entry.pid, force: force) {
            statusMessage = error
        } else {
            statusMessage = nil
        }
        // Give the OS a moment to reap the process, then re-scan.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refresh()
        }
    }
}
