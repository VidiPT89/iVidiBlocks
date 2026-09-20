import SwiftUI

/// The opening presentation. Four tetrominoes drop in and settle above the
/// wordmark, the title catches a sweep of light, then the credit and the two
/// links fade up. Tapping anywhere skips straight to the end.
///
/// The same view backs Menu → About, where it simply stays put instead of
/// dismissing itself.
struct SplashView: View {
    enum Style {
        /// Plays once at launch and calls `onFinish` when it is done.
        case launch
        /// Reached from the menu; waits for the player to close it.
        case about
    }

    let style: Style
    var onFinish: () -> Void

    @EnvironmentObject private var loc: LocalizationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dropProgress: [Double] = [0, 0, 0, 0]
    @State private var titleOpacity: Double = 0
    @State private var titleScale: CGFloat = 0.88
    @State private var shimmerX: CGFloat = -260
    @State private var creditOpacity: Double = 0
    @State private var linksOpacity: Double = 0
    @State private var glow: Double = 0
    @State private var finished = false

    private let assembling: [TetrominoType] = [.l, .o, .t, .i]
    private let website = URL(string: "https://ividi.dev/")!
    private let github = URL(string: "https://github.com/VidiPT89/")!

    var body: some View {
        ZStack {
            BrandBackground()

            RadialGradient(colors: [Color.brandOrange.opacity(0.28 * glow), .clear],
                           center: .center, startRadius: 10, endRadius: 320)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 24)
                fallingPieces
                    .padding(.bottom, 26)
                wordmark
                tagline
                Spacer(minLength: 32)
                credits
                if style == .about { closeButton.padding(.top, 26) }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 28)
        }
        .contentShape(Rectangle())
        .onTapGesture { if style == .launch { finish() } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(style == .launch ? [.isButton] : [])
        .accessibilityHint(style == .launch ? loc.string(.splashSkip) : "")
        .onAppear(perform: animate)
    }

    // MARK: Pieces

    private var fallingPieces: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(assembling.enumerated()), id: \.offset) { index, type in
                PieceThumbnail(type: type, cellSize: 15)
                    .shadow(color: Color.piece(type).opacity(0.55), radius: 12)
                    .offset(y: (1 - dropProgress[index]) * -190)
                    .opacity(dropProgress[index] == 0 ? 0 : 1)
                    .scaleEffect(1 + 0.12 * sin(dropProgress[index] * .pi))
            }
        }
        .frame(height: 70)
    }

    // MARK: Title

    private var wordmark: some View {
        Text(loc.string(.appName))
            .font(.display(58))
            .foregroundStyle(.brandGradient)
            .overlay { if !reduceMotion { shimmer } }
            .scaleEffect(titleScale)
            .opacity(titleOpacity)
            .shadow(color: .brandOrange.opacity(0.4), radius: 22)
            .accessibilityAddTraits(.isHeader)
    }

    private var shimmer: some View {
        LinearGradient(colors: [.clear, .white.opacity(0.85), .clear],
                       startPoint: .leading, endPoint: .trailing)
            .frame(width: 130)
            .rotationEffect(.degrees(18))
            .offset(x: shimmerX)
            .blendMode(.plusLighter)
            .mask(Text(loc.string(.appName)).font(.display(58)))
            .allowsHitTesting(false)
    }

    private var tagline: some View {
        Text(loc.string(.appTagline))
            .font(.subheadline.weight(.medium))
            .tracking(1.2)
            .foregroundStyle(Color.textSecondary)
            .opacity(titleOpacity)
            .padding(.top, 6)
    }

    // MARK: Credits

    private var credits: some View {
        VStack(spacing: 14) {
            Text(loc.string(.splashDevelopedBy))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .opacity(creditOpacity)
                .offset(y: (1 - creditOpacity) * 12)

            VStack(spacing: 8) {
                creditLink(symbol: "globe", title: "ividi.dev", url: website)
                creditLink(symbol: "chevron.left.forwardslash.chevron.right",
                           title: "github.com/VidiPT89", url: github)
            }
            .opacity(linksOpacity)
            .offset(y: (1 - linksOpacity) * 10)
        }
    }

    private func creditLink(symbol: String, title: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
            }
            .foregroundStyle(Color.brandAmber)
            .padding(.horizontal, 16)
            .frame(minHeight: Layout.minimumTapTarget)
            .background(Capsule().fill(Color.bgElevated.opacity(0.65)))
            .overlay(Capsule().strokeBorder(Color.brandAmber.opacity(0.28), lineWidth: 1))
        }
        .accessibilityLabel(title)
    }

    private var closeButton: some View {
        Button(loc.string(.commonClose)) { onFinish() }
            .buttonStyle(BrandButtonStyle(prominent: false, fullWidth: false))
    }

    // MARK: Choreography

    private func animate() {
        guard !reduceMotion else {
            dropProgress = [1, 1, 1, 1]
            titleOpacity = 1
            titleScale = 1
            creditOpacity = 1
            linksOpacity = 1
            glow = 1
            if style == .launch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { finish() }
            }
            return
        }

        for index in assembling.indices {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.58)
                .delay(0.16 + Double(index) * 0.09)) {
                dropProgress[index] = 1
            }
        }

        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.6)) {
            titleOpacity = 1
            titleScale = 1
        }
        withAnimation(.easeOut(duration: 0.8).delay(0.6)) { glow = 1 }
        withAnimation(.easeInOut(duration: 1.0).delay(1.0)) { shimmerX = 260 }
        withAnimation(.easeOut(duration: 0.5).delay(1.3)) { creditOpacity = 1 }
        withAnimation(.easeOut(duration: 0.5).delay(1.6)) { linksOpacity = 1 }

        guard style == .launch else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { finish() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}
