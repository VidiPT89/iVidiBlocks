import SwiftUI

struct MainMenuView: View {
    let onPlay: (GameMode) -> Void

    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var stats: StatsStore
    @EnvironmentObject private var audio: AudioManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sheet: MenuSheet?
    @State private var appeared = false

    private enum MenuSheet: String, Identifiable {
        case settings, stats, howTo, about
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            if !reduceMotion { DriftingPiecesBackdrop() }

            ScrollView {
                VStack(spacing: 22) {
                    header
                    ForEach(Array(GameMode.allCases.enumerated()), id: \.element) { index, mode in
                        ModeCard(mode: mode, record: stats.record(for: mode)) {
                            audio.play(.uiTap)
                            onPlay(mode)
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 26)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8)
                            .delay(0.06 * Double(index)), value: appeared)
                    }
                    secondaryActions
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear { appeared = true }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .settings: SettingsView()
            case .stats: StatsView()
            case .howTo: HowToPlayView()
            case .about: SplashView(style: .about) { sheet = nil }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                LanguageToggle()
                Spacer()
                ThemeToggle()
            }

            Text(loc.string(.appName))
                .font(.display(46))
                .foregroundStyle(.brandGradient)
                .shadow(color: .brandOrange.opacity(0.35), radius: 18)
                .accessibilityAddTraits(.isHeader)

            Text(loc.string(.appTagline))
                .font(.subheadline.weight(.medium))
                .tracking(1.1)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.bottom, 4)
    }

    private var secondaryActions: some View {
        VStack(spacing: 10) {
            menuRow(.menuHowTo, symbol: "questionmark.circle") { sheet = .howTo }
            menuRow(.menuStats, symbol: "chart.bar.fill") { sheet = .stats }
            menuRow(.menuSettings, symbol: "gearshape.fill") { sheet = .settings }
            menuRow(.menuAbout, symbol: "person.crop.circle") { sheet = .about }
        }
        .padding(.top, 4)
    }

    private func menuRow(_ key: LocKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            audio.play(.uiTap)
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.brandAmber)
                    .frame(width: 24)
                Text(loc.string(key))
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .brandCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}

/// One game mode, its blurb and the current personal best.
private struct ModeCard: View {
    let mode: GameMode
    let record: ModeRecord?
    let action: () -> Void

    @EnvironmentObject private var loc: LocalizationManager
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.brandGradient)
                        .frame(width: 52, height: 52)
                    Image(systemName: mode.symbolName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.brandInk)
                }
                .shadow(color: .brandOrange.opacity(0.4), radius: 12, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.string(mode.titleKey))
                        .font(.display(21, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(loc.string(mode.descriptionKey))
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    recordLabel
                }
                Spacer(minLength: 0)
            }
            .padding(Layout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .brandCard()
            .scaleEffect(pressed ? 0.975 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeOut(duration: 0.12)) { pressed = true } }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.18)) { pressed = false } }
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var recordLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 10, weight: .bold))
            Text(recordText)
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(record == nil ? Color.textSecondary : Color.brandAmber)
        .padding(.top, 2)
    }

    private var recordText: String {
        guard let record else { return loc.string(.menuNoRecord) }
        switch mode.scoring {
        case .highestScore:
            return "\(loc.string(.menuBest)) \(record.score.formatted())"
        case .fastestTime:
            return "\(loc.string(.menuBest)) \(TimeFormat.clock(record.time))"
        }
    }
}

/// Faint tetrominoes drifting behind the menu so the screen is never still.
private struct DriftingPiecesBackdrop: View {
    private struct Drifter: Identifiable {
        let id = UUID()
        let type: TetrominoType
        let x: CGFloat
        let size: CGFloat
        let duration: Double
        let delay: Double
    }

    @State private var drifters: [Drifter] = (0..<8).map { index in
        Drifter(type: TetrominoType.allCases[index % TetrominoType.allCases.count],
                x: CGFloat.random(in: 0.05...0.95),
                size: CGFloat.random(in: 8...15),
                duration: Double.random(in: 14...26),
                delay: Double(index) * 1.6)
    }
    @State private var running = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(drifters) { drifter in
                    PieceThumbnail(type: drifter.type, cellSize: drifter.size)
                        .opacity(0.09)
                        .position(x: proxy.size.width * drifter.x,
                                  y: running ? proxy.size.height + 80 : -80)
                        .animation(
                            .linear(duration: drifter.duration)
                                .repeatForever(autoreverses: false)
                                .delay(drifter.delay),
                            value: running
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { running = true }
    }
}
