import SwiftUI

@main
struct NanaApp: App {
    @UIApplicationDelegateAdaptor(NanaAppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            NanaEntryCoordinator()
                .preferredColorScheme(.dark)
                .onOpenURL { NanaURLRouter.shared.receive($0) }
        }
    }
}
