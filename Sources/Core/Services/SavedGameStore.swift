import Foundation
import Combine

/// The single unfinished run the menu offers to continue, kept as one JSON
/// file in Documents. Writes are synchronous: the save happens as the app
/// leaves the foreground, when a deferred write may never get to run.
final class SavedGameStore: ObservableObject {

    @Published private(set) var snapshot: GameSnapshot?

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("saved-run.json")
        load()
    }

    func save(_ snapshot: GameSnapshot) {
        guard snapshot != self.snapshot,
              let data = try? JSONEncoder().encode(snapshot),
              (try? data.write(to: fileURL, options: .atomic)) != nil else { return }
        self.snapshot = snapshot
    }

    func clear() {
        snapshot = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// A file from another version, or one the engine refuses to rebuild,
    /// is deleted instead of being offered as a run that cannot resume.
    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode(GameSnapshot.self, from: data),
              GameEngine(restoring: decoded) != nil else {
            clear()
            return
        }
        snapshot = decoded
    }
}
