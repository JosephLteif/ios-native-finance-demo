import SwiftUI

@main
struct FinanceDemoApp: App {
    init() {
        FinanceDemoShortcuts.updateAppShortcutParameters()
        WatchConnectivityService.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
