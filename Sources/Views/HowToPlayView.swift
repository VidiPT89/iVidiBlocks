import SwiftUI

struct HowToPlayView: View {
    @EnvironmentObject private var loc: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    private let controls: [(symbol: String, key: LocKey)] = [
        ("arrow.left.and.right", .howToControlsMove),
        ("arrow.clockwise", .howToControlsRotate),
        ("arrow.down", .howToControlsSoft),
        ("arrow.down.to.line", .howToControlsHard),
        ("dot.radiowaves.left.and.right", .howToControlsPulse)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        pieceGallery
                        prose(.howToGoal, body: .howToGoalBody)
                        controlsSection
                        prose(.howToScoring, body: .howToScoringBody)
                        prose(.howToTips, body: .howToTipsBody)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(loc.string(.howToTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.string(.commonClose)) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var pieceGallery: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 42))], spacing: 10) {
            ForEach(Shard.all.filter { $0.color.rawValue == $0.shape.rawValue % ShardColor.allCases.count },
                    id: \.self) { shard in
                PieceThumbnail(shard: shard, cellSize: 12)
                    .frame(height: 26)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .brandCard(cornerRadius: 18)
    }

    private func prose(_ title: LocKey, body key: LocKey) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: loc.string(title))
            Text(loc.string(key))
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Layout.cardPadding)
                .brandCard(cornerRadius: 18)
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: loc.string(.howToControls))
            VStack(spacing: 12) {
                ForEach(Array(controls.enumerated()), id: \.offset) { index, entry in
                    HStack(spacing: 14) {
                        Image(systemName: entry.symbol)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.brandAmber)
                            .frame(width: 26)
                        Text(loc.string(entry.key))
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    if index < controls.count - 1 {
                        Divider().overlay(Color.brandOrange.opacity(0.12))
                    }
                }
            }
            .padding(Layout.cardPadding)
            .brandCard(cornerRadius: 18)
        }
    }
}
