import SwiftUI
import ServiceManagement

@MainActor
final class LoginItem: ObservableObject {
    @Published var enabled: Bool = false

    init() { refresh() }

    func refresh() {
        enabled = SMAppService.mainApp.status == .enabled
    }

    func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Status read below reflects whatever actually happened.
        }
        refresh()
    }
}
