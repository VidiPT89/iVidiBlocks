import Foundation

/// Clock and duration formatting. Kept in one place so every screen shows
/// times the same way, with monospaced digits handling the alignment.
enum TimeFormat {

    /// `m:ss.hh` for a run timer, where hundredths actually matter.
    static func clock(_ interval: TimeInterval) -> String {
        // Counted in whole hundredths, with a nudge for binary rounding, so
        // a stored 92.41 does not come back as 92.40999… and show .40.
        let total = Int((max(0, interval) * 100 + 1e-6).rounded(.down))
        return String(format: "%d:%02d.%02d", total / 6000, total / 100 % 60, total % 100)
    }

    /// `m:ss` for a countdown, where hundredths would only be noise.
    static func countdown(_ interval: TimeInterval) -> String {
        let clamped = ceil(max(0, interval))
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
