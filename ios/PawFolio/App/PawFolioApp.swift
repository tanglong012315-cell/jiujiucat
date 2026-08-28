import SwiftUI

@main
struct PawFolioApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .tint(PawTheme.accent)
        }
    }
}

