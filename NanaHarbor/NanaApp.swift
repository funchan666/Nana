import SwiftUI

@main
struct NanaApp: App {
    var body: some Scene {
        WindowGroup {
            NanaEntryCoordinator()
                .preferredColorScheme(.dark)
        }
    }
}
