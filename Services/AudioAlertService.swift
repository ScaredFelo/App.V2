import Foundation
import AVFoundation
import AudioToolbox
import UIKit

@MainActor
public final class AudioAlertService {
    public static let shared = AudioAlertService()

    private init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    public func playRestFinishedAlert() {
        // System sound 1005 (Notification / Alert chime) or custom beep
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
