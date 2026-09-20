import SwiftUI

/// A single strip above the board: hold on the left, the run counters in
/// the middle, the next queue on the right. Laid out horizontally so the
/// playfield itself gets the whole width of the screen.
struct HUDView: View {
    @ObservedObject var model: GameViewModel
    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            holdSlot
            counters
            nextQueue
        }
    }

    // MARK: Hold

    private var holdSlot: some View {
        panel(title: loc.string(.hudHold)) {
            ZStack {
                if let hold = model.holdPiece {
                    PieceThumbnail(type: hold, cellSize: 10,
                                   showGlyph: settings.colorBlindMode)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 44, height: 26)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.holdPiece)
        }
        .accessibilityLabel(loc.string(.hudHold))
    }

    // MARK: Counters

    private var counters: some View {
        VStack(spacing: 6) {
            counter(loc.string(.hudScore), value: model.score.formatted(), prominent: true)

            HStack(spacing: 0) {
                ForEach(secondaryCounters, id: \.0) { label, value, urgent in
                    counter(label, value: value, urgent: urgent)
                        .frame(maxWidth: .infinity)
                }
            }

            chains
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .brandCard(cornerRadius: 14)
    }

    /// Each mode leads with the number that actually decides the run.
    private var secondaryCounters: [(String, String, Bool)] {
        if let remaining = model.linesRemaining {
            return [(loc.string(.hudLines), "\(remaining)", false),
                    (loc.string(.hudTime), TimeFormat.clock(model.elapsed), false)]
        }
        if let remaining = model.timeRemaining {
            return [(loc.string(.hudTime), TimeFormat.countdown(remaining), remaining < 15),
                    (loc.string(.hudLines), "\(model.lines)", false)]
        }
        return [(loc.string(.hudLevel), "\(model.level)", false),
                (loc.string(.hudLines), "\(model.lines)", false)]
    }

    private func counter(_ label: String, value: String,
                         prominent: Bool = false, urgent: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.counter(prominent ? 26 : 15))
                .foregroundStyle(prominent || urgent ? Color.brandOrange : Color.textPrimary)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: value)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    @ViewBuilder
    private var chains: some View {
        HStack(spacing: 6) {
            if model.backToBack {
                chip(text: loc.string(.hudBackToBack), color: .brandAmber)
            }
            if model.combo > 0 {
                chip(text: "\(loc.string(.hudCombo)) \(model.combo)", color: .brandOrange)
            }
        }
        .frame(height: model.backToBack || model.combo > 0 ? nil : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.combo)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.backToBack)
    }

    private func chip(text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .black, design: .rounded))
            .tracking(0.5)
            .foregroundStyle(Color.brandInk)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color))
            .transition(.scale.combined(with: .opacity))
            .lineLimit(1)
    }

    // MARK: Next queue

    private var nextQueue: some View {
        panel(title: loc.string(.hudNext)) {
            VStack(spacing: 6) {
                ForEach(Array(model.preview.enumerated()), id: \.offset) { index, type in
                    PieceThumbnail(type: type,
                                   cellSize: index == 0 ? 9 : 7,
                                   showGlyph: settings.colorBlindMode)
                        .frame(width: 44, height: index == 0 ? 20 : 16)
                        .opacity(index == 0 ? 1 : 0.6 - Double(index) * 0.08)
                }
            }
            .frame(width: 44)
        }
        .accessibilityLabel(loc.string(.hudNext))
    }

    // MARK: Shared chrome

    private func panel<Content: View>(title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Color.textSecondary)
            content()
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .frame(width: 68)
        .brandCard(cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }
}

/// The caption that slides in after a Tetris, T-spin or perfect clear.
struct BannerView: View {
    let banner: Banner

    var body: some View {
        VStack(spacing: 4) {
            Text(banner.text)
                .font(.display(30))
                .foregroundStyle(banner.accent.color)
                .shadow(color: banner.accent.color.opacity(0.7), radius: 16)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let detail = banner.detail {
                Text(detail.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(Color.textPrimary.opacity(0.85))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            Capsule().fill(Color.bgElevated.opacity(0.85))
                .overlay(Capsule().strokeBorder(banner.accent.color.opacity(0.5), lineWidth: 1.5))
        )
        .transition(.asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .opacity.combined(with: .scale(scale: 1.1))
        ))
        .allowsHitTesting(false)
    }
}
