import SwiftUI

@main
struct PortTrayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // No windows; the app lives entirely in the menu bar (LSUIElement).
        Settings { EmptyView() }
    }
}
