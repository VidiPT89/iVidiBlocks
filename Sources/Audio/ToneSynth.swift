import AVFoundation

/// Builds PCM buffers from scratch. The game ships no audio files, so every
/// sound is rendered once at launch from these primitives and then reused.
enum ToneSynth {

    static let sampleRate: Double = 44_100

    enum Waveform {
        case sine
        case square
        case triangle
        case noise

        func sample(phase: Double) -> Float {
            switch self {
            case .sine:
                return Float(sin(phase * 2 * .pi))
            case .square:
                return phase.truncatingRemainder(dividingBy: 1) < 0.5 ? 0.6 : -0.6
            case .triangle:
                let t = phase.truncatingRemainder(dividingBy: 1)
                return Float(t < 0.5 ? (4 * t - 1) : (3 - 4 * t))
            case .noise:
                return Float.random(in: -1...1)
            }
        }
    }

    /// One note in a rendered sound.
    struct Note {
        var frequency: Double
        var start: Double
        var duration: Double
        var amplitude: Double = 0.3
        var waveform: Waveform = .square
        /// Multiplier applied to the frequency across the note, for slides.
        var bend: Double = 1.0
        var attack: Double = 0.004
        var release: Double = 0.08
    }

    static let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                      channels: 2)!

    /// Renders notes into a stereo buffer, mixing overlapping notes together.
    static func render(notes: [Note], length: Double? = nil) -> AVAudioPCMBuffer? {
        let total = length ?? (notes.map { $0.start + $0.duration }.max() ?? 0.2)
        let frames = AVAudioFrameCount(total * sampleRate)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return nil
        }
        buffer.frameLength = frames

        guard let channels = buffer.floatChannelData else { return nil }
        let left = channels[0]
        let right = buffer.format.channelCount > 1 ? channels[1] : channels[0]
        for index in 0..<Int(frames) {
            left[index] = 0
            right[index] = 0
        }

        for note in notes {
            let startFrame = Int(note.start * sampleRate)
            let noteFrames = Int(note.duration * sampleRate)
            guard noteFrames > 0 else { continue }
            var phase = 0.0

            for offset in 0..<noteFrames {
                let index = startFrame + offset
                guard index >= 0, index < Int(frames) else { continue }

                let progress = Double(offset) / Double(noteFrames)
                let frequency = note.frequency * (1 + (note.bend - 1) * progress)
                phase += frequency / sampleRate

                let envelope = amplitudeEnvelope(progress: progress,
                                                 duration: note.duration,
                                                 attack: note.attack,
                                                 release: note.release)
                let value = Float(note.amplitude * envelope) * note.waveform.sample(phase: phase)
                left[index] += value
                right[index] += value
            }
        }

        // Soft clip so stacked notes cannot distort.
        for index in 0..<Int(frames) {
            left[index] = tanh(left[index])
            right[index] = left[index]
        }
        return buffer
    }

    private static func amplitudeEnvelope(progress: Double,
                                          duration: Double,
                                          attack: Double,
                                          release: Double) -> Double {
        let elapsed = progress * duration
        let remaining = duration - elapsed
        var gain = 1.0
        if attack > 0, elapsed < attack { gain *= elapsed / attack }
        if release > 0, remaining < release { gain *= max(0, remaining / release) }
        // Gentle exponential decay keeps the chiptune sounds from feeling flat.
        return gain * pow(1 - progress, 0.35)
    }
}
