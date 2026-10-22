import Foundation
import AVFoundation
import AudioToolbox
import UIKit

@MainActor
public final class AudioAlertService {
    public static let shared = AudioAlertService()

    private var backgroundPlayer: AVAudioPlayer?
    private var alertPlayer: AVAudioPlayer?
    private var restoreSessionTask: Task<Void, Never>?

    private init() {
        configureAudioSession(options: [.mixWithOthers])
    }

    private func configureAudioSession(options: AVAudioSession.CategoryOptions) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: options)
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    public func startBackgroundAudio() {
        restoreSessionTask?.cancel()
        restoreSessionTask = nil
        configureAudioSession(options: [.mixWithOthers])

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
        restoreSessionTask?.cancel()
        configureAudioSession(options: [.duckOthers])

        var alertDuration = 1.8
        do {
            let player = try AVAudioPlayer(data: Self.boxingBellWAVData())
            player.volume = 1.0
            player.prepareToPlay()
            alertPlayer = player
            player.play()
            alertDuration = player.duration
        } catch {
            AudioServicesPlaySystemSound(1005)
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        restoreSessionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((alertDuration + 0.25) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.configureAudioSession(options: [.mixWithOthers])
            self?.restoreSessionTask = nil
        }
    }

    public func playBpmTargetReachedAlert() {
        configureAudioSession(options: [.mixWithOthers])
        AudioServicesPlaySystemSound(1016)

        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }

    private static func silentWAVData(sampleRate: Int = 8000, duration: Double = 1.0) -> Data {
        let sampleCount = Int(Double(sampleRate) * duration)
        return wavData(sampleRate: sampleRate, samples: [Int16](repeating: 0, count: sampleCount))
    }

    private static func boxingBellWAVData(sampleRate: Int = 44100, duration: Double = 1.8) -> Data {
        let sampleCount = Int(Double(sampleRate) * duration)
        var mix = [Double](repeating: 0, count: sampleCount)

        let partials: [(frequency: Double, amplitude: Double, decay: Double)] = [
            (1046.50, 0.55, 4.2),
            (1567.98, 0.34, 5.4),
            (2093.00, 0.24, 6.5),
            (2637.02, 0.16, 7.8),
            (3135.96, 0.10, 9.0)
        ]

        let strikes: [Double] = [0.0, 0.30, 0.60]
        for strike in strikes {
            let start = Int(strike * Double(sampleRate))
            let strikeLength = min(sampleCount - start, Int(1.2 * Double(sampleRate)))
            guard start >= 0, strikeLength > 0 else { continue }

            for offset in 0..<strikeLength {
                let time = Double(offset) / Double(sampleRate)
                let attack = min(1.0, time / 0.003)
                var value = 0.0

                for partial in partials {
                    value += sin(2 * Double.pi * partial.frequency * time)
                        * partial.amplitude
                        * exp(-partial.decay * time)
                }

                if time < 0.02 {
                    value += (1.0 - time / 0.02) * 0.25 * sin(2 * Double.pi * 1800 * time)
                }

                mix[start + offset] += value * attack
            }
        }

        let peak = mix.reduce(0.0) { max($0, abs($1)) }
        let scale = peak > 0 ? 0.92 / peak : 1.0
        let samples = mix.map { value -> Int16 in
            let normalized = max(-1.0, min(1.0, value * scale))
            return Int16(normalized * Double(Int16.max))
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
