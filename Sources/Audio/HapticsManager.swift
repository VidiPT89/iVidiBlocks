import CoreHaptics
import UIKit
import Combine

/// Wraps the simple UIKit generators for common feedback and falls back to
/// a Core Haptics engine for the two events that deserve a custom pattern.
final class HapticsManager: ObservableObject {

    var enabled = true

    private var engine: CHHapticEngine?
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    private var supportsCoreHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    init() {
        prepareGenerators()
        startEngine()
    }

    private func prepareGenerators() {
        light.prepare()
        rigid.prepare()
        heavy.prepare()
        notification.prepare()
    }

    private func startEngine() {
        guard supportsCoreHaptics else { return }
        engine = try? CHHapticEngine()
        // iOS stops the engine when the app backgrounds; bring it straight back.
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        try? engine?.start()
    }

    func move() { tap(light) }
    func rotate() { tap(light) }
    func lock() { tap(rigid) }
    func hardDrop() { tap(heavy) }
    func hold() { tap(light) }

    func gameOver() {
        guard enabled else { return }
        notification.notificationOccurred(.error)
    }

    func newRecord() {
        guard enabled else { return }
        notification.notificationOccurred(.success)
    }

    /// Four quick hits, one per cleared line.
    func tetris() {
        guard enabled else { return }
        let hits = (0..<4).map { index in
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [
                            .init(parameterID: .hapticIntensity, value: 0.8),
                            .init(parameterID: .hapticSharpness, value: 0.7)
                          ],
                          relativeTime: Double(index) * 0.06)
        }
        if !playPattern(events: hits) { tap(heavy) }
    }

    /// A short rising swell, for landing a T-spin.
    func tSpin() {
        guard enabled else { return }
        let rise = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                .init(parameterID: .hapticIntensity, value: 0.6),
                .init(parameterID: .hapticSharpness, value: 0.3)
            ],
            relativeTime: 0,
            duration: 0.28
        )
        let accent = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                .init(parameterID: .hapticIntensity, value: 1.0),
                .init(parameterID: .hapticSharpness, value: 0.9)
            ],
            relativeTime: 0.26
        )
        if !playPattern(events: [rise, accent]) { tap(rigid) }
    }

    func levelUp() {
        guard enabled else { return }
        notification.notificationOccurred(.success)
    }

    private func tap(_ generator: UIImpactFeedbackGenerator) {
        guard enabled else { return }
        generator.impactOccurred()
    }

    private func playPattern(events: [CHHapticEvent]) -> Bool {
        guard let engine,
              let pattern = try? CHHapticPattern(events: events, parameters: []),
              let player = try? engine.makePlayer(with: pattern) else {
            return false
        }
        try? player.start(atTime: CHHapticTimeImmediate)
        return true
    }
}
