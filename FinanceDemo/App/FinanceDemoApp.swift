import SwiftUI

@main
struct FinanceDemoApp: App {
    init() {
        NotificationService.configureForegroundPresentation()
        FinanceDemoShortcuts.updateAppShortcutParameters()
        WatchConnectivityService.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
