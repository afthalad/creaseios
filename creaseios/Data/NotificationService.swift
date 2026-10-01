import UIKit
import UserNotifications
import FirebaseMessaging

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate, MessagingDelegate {
    static let shared = NotificationService()
    var onOpenRoute: ((String) -> Void)?
    var onToken: ((String) -> Void)?
    private(set) var latestToken: String?
    private var pendingRoute: String?

    func configure(application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            application.registerForRemoteNotifications()
        }
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken token: String?) {
        guard let token else { return }
        Task { @MainActor in
            self.latestToken = token
            self.onToken?(token)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .badge, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let route = response.notification.request.content.userInfo["route"] as? String else { return }
        await MainActor.run {
            if let open = onOpenRoute { open(route) } else { pendingRoute = route }
        }
    }

    func flushPendingRoute() {
        guard let r = pendingRoute else { return }
        pendingRoute = nil
        onOpenRoute?(r)
    }

    func follow(_ matchID: String, _ on: Bool) {
        on ? Messaging.messaging().subscribe(toTopic: "match_\(matchID)") : Messaging.messaging().unsubscribe(fromTopic: "match_\(matchID)")
    }

    func remind(_ matchID: String, _ on: Bool) {
        on ? Messaging.messaging().subscribe(toTopic: "reminder_\(matchID)") : Messaging.messaging().unsubscribe(fromTopic: "reminder_\(matchID)")
    }
}
