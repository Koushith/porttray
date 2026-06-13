import SwiftUI
import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let store = PortStore()
    private let loginItem = LoginItem()
    private var cancellables = Set<AnyCancellable>()
    private var badgeTimer: Timer?

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
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: PortListView(store: store, loginItem: loginItem)
        )

        // Keep the badge in sync with the listening-port count. Bound to a
        // dedicated count so switching modes does not change the tray width.
        store.$badgeCount
            .receive(on: RunLoop.main)
            .sink { [weak self] count in
                MainActor.assumeIsolated {
                    self?.statusItem.button?.title = count == 0 ? "" : " \(count)"
                }
            }
            .store(in: &cancellables)

        store.refresh()

        // Refresh the badge in the background while the popover is closed.
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.popover.isShown else { return }
                self.store.refreshBadge()
            }
        }
    }

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
}
