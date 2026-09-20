import Foundation

/// Clock and duration formatting. Kept in one place so every screen shows
/// times the same way, with monospaced digits handling the alignment.
enum TimeFormat {

    /// `m:ss.hh` for a run timer, where hundredths actually matter.
    static func clock(_ interval: TimeInterval) -> String {
        let clamped = max(0, interval)
        let minutes = Int(clamped) / 60
        let seconds = Int(clamped) % 60
        let hundredths = Int((clamped - floor(clamped)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, hundredths)
    }

    /// `m:ss` for a countdown, where hundredths would only be noise.
    static func countdown(_ interval: TimeInterval) -> String {
        let clamped = max(0, interval)
        return String(format: "%d:%02d", Int(clamped) / 60, Int(clamped) % 60)
    }

    /// `4h 12m` style summary for lifetime totals.
    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(total % 60)s" }
        return "\(total)s"
    }
}
