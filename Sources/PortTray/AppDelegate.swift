import SwiftUI
import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let store = PortStore()
    private let loginItem = LoginItem()
    private var cancellables = Set<AnyCancellable>()

    /// Slow, coalesced timer that keeps the menu bar badge roughly current.
    private var badgeTimer: Timer?
    /// Fast timer that only exists while the popover is on screen.
    private var liveTimer: Timer?
    /// False while the display sleeps or the session is locked / switched away.
    private var systemAwake = true

    private enum Interval {
        static let badge: TimeInterval = 15
        static let badgeTolerance: TimeInterval = 5
        static let live: TimeInterval = 3
        static let liveTolerance: TimeInterval = 1
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Screenshot/animation generation mode: render and exit.
        if let i = CommandLine.arguments.firstIndex(of: "--shots") {
            let dir = CommandLine.arguments.indices.contains(i + 1)
                ? CommandLine.arguments[i + 1] : "./screenshots"
            ScreenshotMaker.run(outputDir: dir)
            NSApp.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.image
            button.imagePosition = .imageLeading
            button.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PortListView(store: store, loginItem: loginItem)
        )

        // Keep the badge in sync with the listening-port count. Bound to a
        // dedicated count so switching modes does not change the tray width.
        store.$badgeCount
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] count in
                MainActor.assumeIsolated {
                    self?.statusItem.button?.title = count == 0 ? "" : " \(count)"
                }
            }
            .store(in: &cancellables)

        observeSystemPower()
        store.refresh()
        startBadgeTimer()
    }

    // MARK: - Timers

    private func startBadgeTimer() {
        guard badgeTimer == nil, systemAwake else { return }
        let timer = Timer(timeInterval: Interval.badge, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.popover.isShown else { return }
                self.store.refreshBadge()
            }
        }
        // Tolerance lets macOS batch our wakeups with other timers.
        timer.tolerance = Interval.badgeTolerance
        RunLoop.main.add(timer, forMode: .common)
        badgeTimer = timer
    }

    private func stopBadgeTimer() {
        badgeTimer?.invalidate()
        badgeTimer = nil
    }

    private func startLiveTimer() {
        guard liveTimer == nil else { return }
        let timer = Timer(timeInterval: Interval.live, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.refresh() }
        }
        timer.tolerance = Interval.liveTolerance
        RunLoop.main.add(timer, forMode: .common)
        liveTimer = timer
    }

    private func stopLiveTimer() {
        liveTimer?.invalidate()
        liveTimer = nil
    }

    // MARK: - Sleep / lock

    private func observeSystemPower() {
        let center = NSWorkspace.shared.notificationCenter
        let pause: [Notification.Name] = [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        let resume: [Notification.Name] = [
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        for name in pause {
            center.addObserver(self, selector: #selector(systemWentIdle), name: name, object: nil)
        }
        for name in resume {
            center.addObserver(self, selector: #selector(systemWokeUp), name: name, object: nil)
        }
    }

    @objc private func systemWentIdle() {
        systemAwake = false
        stopBadgeTimer()
        stopLiveTimer()
    }

    @objc private func systemWokeUp() {
        guard !systemAwake else { return }
        systemAwake = true
        store.refreshBadge()
        startBadgeTimer()
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        store.refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    nonisolated func popoverDidShow(_ notification: Notification) {
        MainActor.assumeIsolated { startLiveTimer() }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated { stopLiveTimer() }
    }
}
