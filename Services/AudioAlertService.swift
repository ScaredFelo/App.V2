import Foundation
import AVFoundation
import AudioToolbox
import UIKit

@MainActor
public final class AudioAlertService {
    public static let shared = AudioAlertService()

    private var backgroundPlayer: AVAudioPlayer?
    private var alertPlayer: AVAudioPlayer?

    private init() {
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    public func startBackgroundAudio() {
        configureAudioSession()

        if let player = backgroundPlayer {
            if !player.isPlaying {
                player.play()
            }
            return
        }

        do {
            let player = try AVAudioPlayer(data: Self.silentWAVData())
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            player.play()
            backgroundPlayer = player
        } catch {
            print("No se pudo mantener el audio en segundo plano: \(error.localizedDescription)")
        }
    }

    public func stopBackgroundAudio() {
        backgroundPlayer?.stop()
        backgroundPlayer = nil
    }

    public func playRestFinishedAlert() {
        configureAudioSession()

        do {
            let player = try AVAudioPlayer(data: Self.alertWAVData())
            player.volume = 1
            player.prepareToPlay()
            alertPlayer = player
            player.play()
        } catch {
            AudioServicesPlaySystemSound(1005)
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    public func playBpmTargetReachedAlert() {
        configureAudioSession()
        AudioServicesPlaySystemSound(1016)

        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }

    private static func silentWAVData(sampleRate: Int = 8000, duration: Double = 1.0) -> Data {
        let sampleCount = Int(Double(sampleRate) * duration)
        return wavData(sampleRate: sampleRate, samples: [Int16](repeating: 0, count: sampleCount))
    }

    private static func alertWAVData(sampleRate: Int = 44100, duration: Double = 0.5) -> Data {
        let sampleCount = Int(Double(sampleRate) * duration)
        var samples = [Int16](repeating: 0, count: sampleCount)

        let beeps: [(start: Double, end: Double, frequency: Double)] = [
            (0.00, 0.16, 880.0),
            (0.22, 0.42, 1174.66)
        ]

        for beep in beeps {
            let start = max(0, Int(beep.start * Double(sampleRate)))
            let end = min(sampleCount, Int(beep.end * Double(sampleRate)))
            guard start < end else { continue }

            let length = Double(end - start)
            for index in start..<end {
                let time = Double(index) / Double(sampleRate)
                let progress = Double(index - start) / length
                let envelope = sin(Double.pi * progress)
                let value = sin(2 * Double.pi * beep.frequency * time) * envelope * 0.35
                samples[index] = Int16(max(-1, min(1, value)) * Double(Int16.max))
            }
        }

        return wavData(sampleRate: sampleRate, samples: samples)
    }

    private static func wavData(sampleRate: Int, samples: [Int16]) -> Data {
        let dataSize = samples.count * 2
        var data = Data()

        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndianValue = value.littleEndian
            withUnsafeBytes(of: &littleEndianValue) { bytes in
                data.append(contentsOf: bytes)
            }
        }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))

        for sample in samples {
            append(UInt16(bitPattern: sample))
        }

        return data
    }
}
