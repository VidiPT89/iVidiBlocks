import AVFoundation
import Combine

enum SoundEffect: Hashable {
    case move
    case rotate
    case lock
    case hardDrop
    case hold
    case clear(Int)
    case tSpin
    case perfectClear
    case levelUp
    case gameOver
    case uiTap

    /// Louder events briefly duck the music so they cut through.
    var ducksMusic: Bool {
        switch self {
        case .clear, .tSpin, .perfectClear, .levelUp, .gameOver: return true
        default: return false
        }
    }
}

/// Plays the synthesised sound effects and the looping backing track.
/// Buffers are rendered once on a background queue at startup.
final class AudioManager: ObservableObject {

    var sfxEnabled = true
    var musicEnabled = false {
        didSet {
            guard musicEnabled != oldValue else { return }
            musicEnabled ? startMusic() : stopMusic()
        }
    }

    private let engine = AVAudioEngine()
    private let sfxPlayers: [AVAudioPlayerNode]
    private let musicPlayer = AVAudioPlayerNode()
    private var buffers: [SoundEffect: AVAudioPCMBuffer] = [:]
    private var musicBuffer: AVAudioPCMBuffer?
    private var nextPlayer = 0
    private var isRunning = false
    private var duckWorkItem: DispatchWorkItem?

    private let musicVolume: Float = 0.22
    private let prepareQueue = DispatchQueue(label: "dev.ividi.itetris.audio", qos: .utility)

    init() {
        // A handful of voices so overlapping effects never cut each other off.
        sfxPlayers = (0..<6).map { _ in AVAudioPlayerNode() }
        prepareQueue.async { [weak self] in self?.prepare() }
        observeInterruptions()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// A phone call or a route change stops the engine. Without this the app
    /// stays silent until it is relaunched.
    private func observeInterruptions() {
        let centre = NotificationCenter.default
        centre.addObserver(self, selector: #selector(handleInterruption),
                           name: AVAudioSession.interruptionNotification, object: nil)
        centre.addObserver(self, selector: #selector(handleConfigurationChange),
                           name: .AVAudioEngineConfigurationChange, object: engine)
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            isRunning = false
        case .ended:
            DispatchQueue.main.async { [weak self] in self?.restart() }
        @unknown default:
            break
        }
    }

    @objc private func handleConfigurationChange() {
        DispatchQueue.main.async { [weak self] in self?.restart() }
    }

    private func restart() {
        guard musicBuffer != nil else { return }
        startEngine()
    }

    private func prepare() {
        let format = ToneSynth.format
        var rendered: [SoundEffect: AVAudioPCMBuffer] = [:]
        for effect in SoundEffect.allBaseCases {
            rendered[effect] = ToneSynth.render(notes: notes(for: effect))
        }
        let music = ToneSynth.render(notes: Self.musicNotes(), length: Self.musicLoopLength)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.buffers = rendered
            self.musicBuffer = music
            self.attachAndStart(format: format)
        }
    }

    private func attachAndStart(format: AVAudioFormat) {
        for player in sfxPlayers {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        engine.attach(musicPlayer)
        engine.connect(musicPlayer, to: engine.mainMixerNode, format: format)
        musicPlayer.volume = musicVolume
        startEngine()
    }

    private func startEngine() {
        configureSession()
        do {
            try engine.start()
            isRunning = true
            for player in sfxPlayers where !player.isPlaying { player.play() }
            if musicEnabled { startMusic() }
        } catch {
            isRunning = false
        }
    }

    private func configureSession() {
        // Ambient with mixing so the player's own music keeps playing if
        // they would rather listen to that.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    // MARK: Playback

    func play(_ effect: SoundEffect) {
        guard sfxEnabled, isRunning, let buffer = buffers[effect.normalised] else { return }
        let player = sfxPlayers[nextPlayer]
        nextPlayer = (nextPlayer + 1) % sfxPlayers.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
        if effect.ducksMusic { duck() }
    }

    private func duck() {
        guard musicEnabled else { return }
        duckWorkItem?.cancel()
        musicPlayer.volume = musicVolume * 0.3
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.musicPlayer.volume = self.musicVolume
        }
        duckWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
    }

    private func startMusic() {
        guard isRunning, let buffer = musicBuffer else { return }
        musicPlayer.stop()
        musicPlayer.volume = musicVolume
        musicPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
        musicPlayer.play()
    }

    private func stopMusic() {
        musicPlayer.stop()
    }

    func pauseAll() {
        guard isRunning else { return }
        musicPlayer.pause()
    }

    func resumeAll() {
        guard isRunning, musicEnabled else { return }
        musicPlayer.play()
    }

    // MARK: Sound design

    private func notes(for effect: SoundEffect) -> [ToneSynth.Note] {
        switch effect {
        case .move:
            return [.init(frequency: 220, start: 0, duration: 0.045,
                          amplitude: 0.14, waveform: .square)]
        case .rotate:
            return [.init(frequency: 330, start: 0, duration: 0.06,
                          amplitude: 0.16, waveform: .square, bend: 1.2)]
        case .uiTap:
            return [.init(frequency: 520, start: 0, duration: 0.05,
                          amplitude: 0.14, waveform: .triangle, bend: 1.15)]
        case .lock:
            return [.init(frequency: 150, start: 0, duration: 0.08,
                          amplitude: 0.22, waveform: .square, bend: 0.75)]
        case .hold:
            return [.init(frequency: 400, start: 0, duration: 0.07,
                          amplitude: 0.16, waveform: .triangle, bend: 1.35)]
        case .hardDrop:
            return [
                .init(frequency: 300, start: 0, duration: 0.10,
                      amplitude: 0.24, waveform: .square, bend: 0.4),
                .init(frequency: 90, start: 0.03, duration: 0.12,
                      amplitude: 0.18, waveform: .noise)
            ]
        case let .clear(lines):
            // Each extra line adds a step to a rising arpeggio.
            let scale: [Double] = [523.25, 659.25, 783.99, 1046.50, 1318.51]
            return (0..<max(1, min(lines, 4)) + 1).map { step in
                .init(frequency: scale[min(step, scale.count - 1)],
                      start: Double(step) * 0.055,
                      duration: 0.18,
                      amplitude: 0.20,
                      waveform: .triangle)
            }
        case .tSpin:
            return [
                .init(frequency: 440, start: 0, duration: 0.22,
                      amplitude: 0.20, waveform: .sine, bend: 1.6),
                .init(frequency: 660, start: 0.06, duration: 0.22,
                      amplitude: 0.14, waveform: .sine, bend: 1.4)
            ]
        case .perfectClear:
            let chord: [Double] = [523.25, 659.25, 783.99, 1046.50]
            return chord.enumerated().map { index, frequency in
                .init(frequency: frequency, start: Double(index) * 0.07,
                      duration: 0.55, amplitude: 0.18, waveform: .sine)
            }
        case .levelUp:
            return [
                .init(frequency: 392, start: 0, duration: 0.12, amplitude: 0.20, waveform: .square),
                .init(frequency: 523.25, start: 0.10, duration: 0.12, amplitude: 0.20, waveform: .square),
                .init(frequency: 659.25, start: 0.20, duration: 0.22, amplitude: 0.22, waveform: .square)
            ]
        case .gameOver:
            return [
                .init(frequency: 392, start: 0, duration: 0.22, amplitude: 0.22, waveform: .triangle),
                .init(frequency: 311.13, start: 0.20, duration: 0.24, amplitude: 0.22, waveform: .triangle),
                .init(frequency: 233.08, start: 0.42, duration: 0.45, amplitude: 0.24,
                      waveform: .triangle, bend: 0.85)
            ]
        }
    }

    // MARK: Backing track

    private static let musicLoopLength: Double = 16

    /// A calm eight-bar loop in A minor: walking bass under a sparse
    /// arpeggio, quiet enough to sit behind the effects.
    private static func musicNotes() -> [ToneSynth.Note] {
        let bassLine: [Double] = [110.00, 110.00, 146.83, 146.83,
                                  164.81, 164.81, 130.81, 130.81]
        let arpeggios: [[Double]] = [
            [440.00, 523.25, 659.25], [440.00, 523.25, 659.25],
            [587.33, 698.46, 880.00], [587.33, 698.46, 880.00],
            [659.25, 783.99, 987.77], [659.25, 783.99, 987.77],
            [523.25, 659.25, 783.99], [523.25, 659.25, 783.99]
        ]

        var notes: [ToneSynth.Note] = []
        let barLength = musicLoopLength / Double(bassLine.count)

        for (bar, root) in bassLine.enumerated() {
            let barStart = Double(bar) * barLength
            notes.append(.init(frequency: root, start: barStart, duration: barLength * 0.9,
                               amplitude: 0.16, waveform: .triangle, release: 0.3))

            let pattern = arpeggios[bar]
            for step in 0..<6 {
                notes.append(.init(frequency: pattern[step % pattern.count],
                                   start: barStart + Double(step) * (barLength / 6),
                                   duration: barLength / 6 * 0.8,
                                   amplitude: 0.055,
                                   waveform: .sine,
                                   release: 0.12))
            }
        }
        return notes
    }
}

private extension SoundEffect {
    /// Line-clear sounds are rendered per line count, everything else is
    /// stored under itself.
    var normalised: SoundEffect {
        if case let .clear(lines) = self { return .clear(min(max(lines, 1), 4)) }
        return self
    }

    static var allBaseCases: [SoundEffect] {
        [.move, .rotate, .lock, .hardDrop, .hold, .tSpin,
         .perfectClear, .levelUp, .gameOver, .uiTap,
         .clear(1), .clear(2), .clear(3), .clear(4)]
    }
}
