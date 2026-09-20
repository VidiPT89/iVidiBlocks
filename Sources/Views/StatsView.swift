import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var stats: StatsStore
    @Environment(\.dismiss) private var dismiss

    private var hasHistory: Bool { stats.lifetime.gamesPlayed > 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackground()

                if hasHistory {
                    ScrollView {
                        VStack(spacing: 20) {
                            recordsSection
                            lifetimeSection
                        }
                        .padding(20)
                    }
                } else {
                    emptyState
                }
            }
            .navigationTitle(loc.string(.statsTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.string(.commonClose)) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 42))
                .foregroundStyle(Color.brandAmber.opacity(0.7))
            Text(loc.string(.statsEmpty))
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: loc.string(.statsRecords))
            VStack(spacing: 12) {
                ForEach(GameMode.allCases) { mode in
                    recordRow(for: mode)
                    if mode != GameMode.allCases.last {
                        Divider().overlay(Color.brandOrange.opacity(0.12))
                    }
                }
            }
            .padding(Layout.cardPadding)
            .brandCard(cornerRadius: 18)
        }
    }

    private func recordRow(for mode: GameMode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: mode.symbolName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.brandAmber)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(loc.string(mode.titleKey))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                if let record = stats.record(for: mode) {
                    Text(secondaryText(for: mode, record: record))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer()

            Text(primaryText(for: mode))
                .font(.counter(17))
                .foregroundStyle(stats.record(for: mode) == nil
                                 ? Color.textSecondary : Color.brandOrange)
        }
        .accessibilityElement(children: .combine)
    }

    private func primaryText(for mode: GameMode) -> String {
        guard let record = stats.record(for: mode) else { return "—" }
        switch mode.scoring {
        case .highestScore: return record.score.formatted()
        case .fastestTime: return TimeFormat.clock(record.time)
        }
    }

    private func secondaryText(for mode: GameMode, record: ModeRecord) -> String {
        switch mode.scoring {
        case .highestScore:
            return "\(loc.string(.hudLines)) \(record.lines) · \(loc.string(.hudLevel)) \(record.level)"
        case .fastestTime:
            return "\(loc.string(.hudScore)) \(record.score.formatted())"
        }
    }

    private var lifetimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: loc.string(.statsLifetime))
            VStack(spacing: 10) {
                StatRow(label: loc.string(.statsGames),
                        value: stats.lifetime.gamesPlayed.formatted())
                StatRow(label: loc.string(.statsPieces),
                        value: stats.lifetime.piecesPlaced.formatted())
                StatRow(label: loc.string(.statsLines),
                        value: stats.lifetime.linesCleared.formatted())
                StatRow(label: loc.string(.statsTetrises),
                        value: stats.lifetime.tetrises.formatted(),
                        highlighted: true)
                StatRow(label: loc.string(.statsTSpins),
                        value: stats.lifetime.tSpins.formatted(),
                        highlighted: true)
                StatRow(label: loc.string(.statsTimePlayed),
                        value: TimeFormat.duration(stats.lifetime.timePlayed))
            }
            .padding(Layout.cardPadding)
            .brandCard(cornerRadius: 18)
        }
    }
}
