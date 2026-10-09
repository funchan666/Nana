import SwiftUI

@main
struct NanaApp: App {
    @UIApplicationDelegateAdaptor(NanaAppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            NanaEntryCoordinator()
                .ignoresSafeArea(.all)
                .preferredColorScheme(.dark)
                .onOpenURL { NanaURLRouter.shared.receive($0) }
        }
    }
}
