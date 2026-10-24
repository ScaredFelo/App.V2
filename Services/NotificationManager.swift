import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()

    private let restFinishedIdentifier = "com.jordiferres.appgym.rest.finished"

    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error {
                print("[Notifications] Error solicitando permiso: \(error.localizedDescription)")
            } else {
                print("[Notifications] Permiso concedido: \(granted)")
            }
        }
    }

    func scheduleRestFinishedNotification(after seconds: TimeInterval) {
        cancelRestFinishedNotification()

        guard seconds > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Descanso completado"
        content.body = "Ya puedes empezar la siguiente serie."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, seconds),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: restFinishedIdentifier,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[Notifications] Error programando aviso de descanso: \(error.localizedDescription)")
            } else {
                print("[Notifications] Aviso de descanso programado en \(Int(seconds))s")
            }
        }
    }

    func cancelRestFinishedNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [restFinishedIdentifier]
        )
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [restFinishedIdentifier]
        )
    }
}
