import SwiftUI

@main
struct FinanceDemoApp: App {
    init() {
        FinanceDemoShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
