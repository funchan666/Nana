import UIKit

final class NanaAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task { @MainActor in
            NanaPushTokenCoordinator.shared.start()
            NanaCoinStore.shared.start()
            NanaCoinStore.shared.wakeRecovery()
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Task { @MainActor in
            NanaPushTokenCoordinator.shared.start()
            NanaCoinStore.shared.start()
            NanaCoinStore.shared.wakeRecovery()
        }
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        Task { @MainActor in NanaCoinStore.shared.wakeRecovery() }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            NanaPushTokenCoordinator.shared.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            NanaPushTokenCoordinator.shared.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
        }
    }
}
