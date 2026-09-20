import SwiftUI

struct GameOverView: View {
    @ObservedObject var model: GameViewModel
    let result: GameViewModel.GameResult
    let onPlayAgain: () -> Void
    let onExit: () -> Void

    @EnvironmentObject private var loc: LocalizationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false
    @State private var trophyGlow = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 16) {
                if result.isNewRecord { recordBadge }

                Text(model.resultTitle(for: result.reason))
                    .font(.display(28))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                summary

                VStack(spacing: 10) {
                    Button(loc.string(.gameOverPlayAgain), action: onPlayAgain)
                        .buttonStyle(BrandButtonStyle())
                    Button(loc.string(.gameOverMenu), action: onExit)
                        .buttonStyle(BrandButtonStyle(prominent: false))
                }
            }
            .padding(26)
            .frame(maxWidth: 340)
            .brandCard(cornerRadius: 26)
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 30)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { appeared = true }
            guard result.isNewRecord, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                trophyGlow = true
            }
        }
    }

    private var recordBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "trophy.fill")
            Text(loc.string(.gameOverNewRecord).uppercased())
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(1.6)
        }
        .foregroundStyle(Color.brandInk)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(.brandGradient))
        .shadow(color: .brandOrange.opacity(trophyGlow ? 0.85 : 0.3),
                radius: trophyGlow ? 22 : 10)
    }

    private var summary: some View {
        VStack(spacing: 10) {
            StatRow(label: loc.string(.hudScore),
                    value: result.score.formatted(),
                    highlighted: true)
            Divider().overlay(Color.brandOrange.opacity(0.14))
            StatRow(label: loc.string(.hudLines), value: "\(result.lines)")
            Divider().overlay(Color.brandOrange.opacity(0.14))
            StatRow(label: loc.string(.hudLevel), value: "\(result.level)")
            Divider().overlay(Color.brandOrange.opacity(0.14))
            StatRow(label: loc.string(.hudTime), value: TimeFormat.clock(result.time))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.bgSecondary.opacity(0.7))
        )
    }
}
