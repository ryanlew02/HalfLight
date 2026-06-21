//
//  SoundManager.swift
//  HalfLight
//
//  Tiny, satisfying feedback sounds — synthesized at runtime so no audio files are
//  bundled — paired with light haptics. Each effect is a short sequence of
//  enveloped sine tones (clean, click-free) tuned to feel pleasant and a little
//  addictive: bright major notes for wins, a soft low note for misses.
//
//  Uses the `.ambient` audio session so effects mix with the user's music and
//  respect the silent switch. Both sound and haptics honor user settings.
//

import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class SoundManager {
    static let shared = SoundManager()

    /// The catalog of feedback effects.
    enum Effect {
        case tap          // light UI tap (navigation, stepping forward, buttons)
        case correct      // quiz answer right
        case wrong        // quiz answer wrong / an error
        case reward       // XP earned (lesson / dream / quest)
        case achievement  // a badge unlocked
        case shimmer      // AI result arrived (analysis, auto-tags)
        case levelUp      // reserved for bigger milestones
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var cache: [Effect: AVAudioPCMBuffer] = [:]
    private var started = false

    private var soundEnabled: Bool {
        UserDefaults.standard.object(forKey: "soundEffectsEnabled") as? Bool ?? true
    }
    private var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    private init() {}

    /// Play an effect (plus its matching haptic). No-ops gracefully when disabled
    /// or if audio can't start. Safe to call from anywhere on the main actor.
    func play(_ effect: Effect) {
        haptic(for: effect)
        guard soundEnabled else { return }
        startIfNeeded()
        guard started else { return }

        let buffer: AVAudioPCMBuffer
        if let cached = cache[effect] {
            buffer = cached
        } else {
            buffer = makeBuffer(for: effect)
            cache[effect] = buffer
        }
        // `.interrupts` so rapid taps replace rather than queue up and lag.
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    // MARK: - Engine

    private func startIfNeeded() {
        guard !started else { return }
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        // `.ambient` mixes with the user's music and respects the silent switch.
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            player.play()
            started = true
        } catch {
            started = false
        }
    }

    // MARK: - Haptics

    private func haptic(for effect: Effect) {
        guard hapticsEnabled else { return }
        #if canImport(UIKit) && !os(watchOS)
        switch effect {
        case .tap:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .correct, .reward, .shimmer:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .wrong:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .achievement, .levelUp:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        #endif
    }

    // MARK: - Tone synthesis

    /// The note sequence (frequency in Hz, duration in seconds) and volume for each
    /// effect. Bright ascending major notes read as "good"; a low fall reads as "no".
    private func notes(for effect: Effect) -> (sequence: [(freq: Double, dur: Double)], volume: Float) {
        let c5 = 523.25, d5 = 587.33, e5 = 659.25, g5 = 783.99
        let a5 = 880.00, c6 = 1046.50, e6 = 1318.51
        let a3 = 220.00, f3 = 174.61

        switch effect {
        case .tap:
            return ([(a5, 0.05)], 0.16)
        case .correct:
            return ([(g5, 0.085), (c6, 0.13)], 0.30)
        case .wrong:
            return ([(a3, 0.12), (f3, 0.17)], 0.28)
        case .reward:
            return ([(c5, 0.07), (e5, 0.07), (g5, 0.07), (c6, 0.16)], 0.30)
        case .achievement:
            return ([(c5, 0.07), (e5, 0.07), (g5, 0.07), (c6, 0.09), (e6, 0.20)], 0.32)
        case .shimmer:
            // High, sparkly two-note rise — reads as "magic happened".
            return ([(a5, 0.07), (e6, 0.14)], 0.24)
        case .levelUp:
            return ([(c5, 0.06), (d5, 0.06), (e5, 0.06), (g5, 0.06), (c6, 0.20)], 0.30)
        }
    }

    private func makeBuffer(for effect: Effect) -> AVAudioPCMBuffer {
        let (sequence, volume) = notes(for: effect)
        let sampleRate = format.sampleRate
        let totalDuration = sequence.reduce(0.0) { $0 + $1.dur }
        let frameCount = AVAudioFrameCount(totalDuration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]

        var frame = 0
        for note in sequence {
            let count = Int(note.dur * sampleRate)
            let attack = max(1, Int(0.005 * sampleRate))      // 5ms ramp-in
            let release = max(1, Int(Double(count) * 0.55))   // long tail
            let releaseStart = count - release

            for i in 0..<count where frame < Int(frameCount) {
                let envelope: Double
                if i < attack {
                    envelope = Double(i) / Double(attack)
                } else if i >= releaseStart {
                    envelope = max(0, Double(count - i) / Double(release))
                } else {
                    envelope = 1
                }
                let t = Double(i) / sampleRate
                samples[frame] = Float(sin(2 * .pi * note.freq * t) * envelope) * volume
                frame += 1
            }
        }
        return buffer
    }
}
