import SwiftUI

@MainActor
final class PortStore: ObservableObject {
    struct Toast: Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    @Published private(set) var snapshot = PortSnapshot()
    @Published private(set) var loaded = false
    @Published private(set) var badgeCount: Int = 0
    @Published private(set) var killing: Set<String> = []
    @Published private(set) var toast: Toast?

    private let previewMode: Bool
    private var scanInFlight = false
    private var rescanQueued = false
    private var badgeInFlight = false
    private var toastClear: DispatchWorkItem?

    /// Live store backed by the kernel socket table.
    init() { previewMode = false }

    /// Static store for rendering README screenshots from demo data.
    init(preview snapshot: PortSnapshot) {
        previewMode = true
        setPreview(snapshot)
    }

    func setPreview(_ snap: PortSnapshot) {
        snapshot = snap
        loaded = true
        badgeCount = snap.counts[.listening] ?? 0
    }

    /// One background kernel walk refreshes all three tabs and the badge.
    /// Overlapping requests coalesce into at most one follow-up scan, and
    /// nothing is published unless it actually changed.
    func refresh() {
        guard !previewMode else { return }
        guard !scanInFlight else { rescanQueued = true; return }
        scanInFlight = true
        Task.detached(priority: .utility) { [weak self] in
            let snap = Presenter.snapshot(PortScanner.scanAll())
            await self?.apply(snap)
        }
    }

    /// Refreshes only the menu bar badge (listening count; touches no names).
    func refreshBadge() {
        guard !previewMode, !badgeInFlight, !scanInFlight else { return }
        badgeInFlight = true
        Task.detached(priority: .background) { [weak self] in
            let count = PortScanner.listeningCount()
            await self?.applyBadge(count)
        }
    }

    func kill(_ row: PortRow, mode: ScanMode) {
        guard !previewMode, !killing.contains(row.id) else { return }
        killing.insert(row.id)
        let pid = row.entry.pid
        Task.detached(priority: .userInitiated) { [weak self] in
            let error = PortScanner.kill(pid: pid)
            await self?.finishKill(row, mode: mode, error: error)
        }
    }

    func showToast(_ text: String, isError: Bool = false) {
        toast = Toast(text: text, isError: isError)
        toastClear?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? 5 : 3.5), execute: work)
    }

    private func apply(_ snap: PortSnapshot) {
        scanInFlight = false
        if snapshot != snap { snapshot = snap }
        if !loaded { loaded = true }
        let count = snap.counts[.listening] ?? 0
        if badgeCount != count { badgeCount = count }
        if rescanQueued {
            rescanQueued = false
            refresh()
        }
    }

    private func applyBadge(_ count: Int) {
        badgeInFlight = false
        if badgeCount != count { badgeCount = count }
    }

    private func finishKill(_ row: PortRow, mode: ScanMode, error: String?) {
        killing.remove(row.id)
        if let error {
            showToast(error, isError: true)
        } else {
            showToast(mode == .listening
                      ? "\(row.name) stopped · :\(row.port) is free"
                      : "\(row.name) stopped")
        }
        refresh()
    }
}
