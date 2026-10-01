import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseMessaging

final class AppDelegate: NSObject, UIApplicationDelegate {
    private(set) var env: AppEnvironment!

    func application(_ app: UIApplication,
                     didFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        if Auth.auth().currentUser?.isAnonymous == true { try? Auth.auth().signOut() }
        env = AppEnvironment()
        NotificationService.shared.configure(application: app)
        return true
    }

    func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        Messaging.messaging().apnsToken = token
        Auth.auth().setAPNSToken(token, type: .unknown)
    }

    func application(_ app: UIApplication, didReceiveRemoteNotification info: [AnyHashable: Any],
                     fetchCompletionHandler done: @escaping (UIBackgroundFetchResult) -> Void) {
        done(Auth.auth().canHandleNotification(info) ? .noData : .newData)
    }
}

@main
struct CreaseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(delegate.env)
                .environment(delegate.env.router)
                .environment(delegate.env.session)
                .environment(delegate.env.settings)
                .onOpenURL { url in _ = Auth.auth().canHandle(url) }
        }
    }
}
