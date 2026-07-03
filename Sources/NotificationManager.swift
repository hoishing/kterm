import UserNotifications

/// Thin wrapper around `UNUserNotificationCenter` for terminal bell /
/// OSC 9 / OSC 777 desktop notifications.
///
/// Whether a given notification should be suppressed (because the surface
/// that raised it is the one the user is already looking at) is decided by
/// the caller — see `AppModel`'s `onNotification` wiring — so `post` here
/// just requests authorization once and posts unconditionally.
@MainActor
enum NotificationManager {
    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// `terminalID` is stashed in `userInfo` so a tap on the notification can
    /// be routed back to the exact tab that raised it — see
    /// `AppDelegate.userNotificationCenter(_:didReceive:)`.
    static func post(title: String, body: String, terminalID: UUID) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["terminalID": terminalID.uuidString]
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
