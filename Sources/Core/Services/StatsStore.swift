import Foundation
import Combine

/// Best result for one mode. Marathon and Ultra rank on score, Sprint ranks
/// on the fastest time to clear its 40 lines.
struct ModeRecord: Codable, Equatable {
    var score: Int = 0
    var lines: Int = 0
    var level: Int = 1
    var time: TimeInterval = 0
    var achievedAt: Date = .distantPast

    var isSet: Bool { achievedAt != .distantPast }
}

struct LifetimeStats: Codable, Equatable {
    var gamesPlayed = 0
    var piecesPlaced = 0
    var linesCleared = 0
    var tetrises = 0
    var tSpins = 0
    var timePlayed: TimeInterval = 0
}

private struct StatsPayload: Codable {
    var records: [String: ModeRecord] = [:]
    var lifetime = LifetimeStats()
}

/// Records and lifetime totals, kept as one JSON file in Documents. Saves
/// are debounced and run off the main thread so a write never lands in the
/// middle of a frame.
final class StatsStore: ObservableObject {

    @Published private(set) var records: [GameMode: ModeRecord] = [:]
    @Published private(set) var lifetime = LifetimeStats()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "dev.ividi.itetris.stats", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("stats.json")
        load()
    }

    func record(for mode: GameMode) -> ModeRecord? {
        guard let record = records[mode], record.isSet else { return nil }
        return record
    }

    /// Folds a finished run into the stored history.
    /// - Returns: `true` when the run beat the existing record for its mode.
    @discardableResult
    func submit(mode: GameMode,
                score: Int,
                lines: Int,
                level: Int,
                time: TimeInterval,
                reason: GameOverReason,
                runStats: RunStats) -> Bool {
        lifetime.gamesPlayed += 1
        lifetime.piecesPlaced += runStats.piecesPlaced
        lifetime.linesCleared += runStats.linesCleared
        lifetime.tetrises += runStats.tetrises
        lifetime.tSpins += runStats.tSpins
        lifetime.timePlayed += time

        let candidate = ModeRecord(score: score, lines: lines, level: level,
                                   time: time, achievedAt: Date())
        let beaten = isBetter(candidate, than: records[mode], mode: mode, reason: reason)
        if beaten { records[mode] = candidate }

        scheduleSave()
        return beaten
    }

    func reset() {
        records = [:]
        lifetime = LifetimeStats()
        scheduleSave()
    }

    private func isBetter(_ candidate: ModeRecord,
                          than existing: ModeRecord?,
                          mode: GameMode,
                          reason: GameOverReason) -> Bool {
        guard let existing, existing.isSet else {
            // An unfinished Sprint has no meaningful time to record.
            return mode.scoring == .highestScore || reason == .targetReached
        }
        switch mode.scoring {
        case .highestScore:
            return candidate.score > existing.score
        case .fastestTime:
            guard reason == .targetReached else { return false }
            return candidate.time < existing.time
        }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(StatsPayload.self, from: data) else {
            return
        }
        lifetime = payload.lifetime
        records = payload.records.reduce(into: [:]) { result, entry in
            if let mode = GameMode(rawValue: entry.key) { result[mode] = entry.value }
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let payload = StatsPayload(
            records: records.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value },
            lifetime: lifetime
        )
        let url = fileURL
        let item = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(payload) else { return }
            try? data.write(to: url, options: .atomic)
        }
        saveWorkItem = item
        queue.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    /// Flushes any pending write immediately, for when the app backgrounds.
    func flush() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let payload = StatsPayload(
            records: records.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value },
            lifetime: lifetime
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
