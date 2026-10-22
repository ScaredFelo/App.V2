import Foundation
import AVFoundation
import AudioToolbox
import UIKit
import UserNotifications

@MainActor
public final class AudioAlertService {
    public static let shared = AudioAlertService()

    private let restNotificationID = "appgym.rest.finished"

    private init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    public func scheduleRestFinishedNotification(after seconds: Int) {
        guard seconds > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Es hora de dar-le"
        content.body = "Es hora de dar-le"
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(max(1, seconds)),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: restNotificationID,
            content: content,
            trigger: trigger
        )

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [restNotificationID])
        center.add(request) { error in
            if let error = error {
                print("No se pudo programar la notificación de descanso: \(error.localizedDescription)")
            }
        }
    }

    public func cancelRestFinishedNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [restNotificationID])
        center.removeDeliveredNotifications(withIdentifiers: [restNotificationID])
    }

    public func playRestFinishedAlert() {
        cancelRestFinishedNotification()

        // Sonido de alerta del sistema
        AudioServicesPlaySystemSound(1005)

        // Haptic feedback notification
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    public func playBpmTargetReachedAlert() {
        // System sound 1016 (Tock / Prompt) or alert
        AudioServicesPlaySystemSound(1016)

        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }
}
