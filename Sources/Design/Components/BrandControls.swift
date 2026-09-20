import SwiftUI

/// Primary call to action: the orange gradient pill used for Play, Resume
/// and anything else that moves the player forward.
struct BrandButtonStyle: ButtonStyle {
    var prominent: Bool = true
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.display(18, weight: .bold))
            .foregroundStyle(prominent ? Color.brandInk : Color.textPrimary)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Layout.minimumTapTarget)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background {
                let shape = Capsule(style: .continuous)
                if prominent {
                    shape.fill(.brandGradient)
                        .shadow(color: .brandOrange.opacity(0.45), radius: 16, y: 6)
                } else {
                    shape.fill(Color.bgElevated)
                        .overlay(shape.strokeBorder(Color.brandOrange.opacity(0.35), lineWidth: 1.5))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Small round icon button, used for pause, close and the theme toggle.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = Layout.minimumTapTarget

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(Color.textPrimary)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.bgElevated))
            .overlay(Circle().strokeBorder(Color.brandOrange.opacity(0.28), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// The `PT | EN` pill. Both options stay visible so the player can see what
/// they are switching to.
struct LanguageToggle: View {
    @EnvironmentObject private var loc: LocalizationManager
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppLanguage.allCases) { language in
                let selected = loc.language == language
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                        loc.setLanguage(language)
                    }
                } label: {
                    Text(language.shortName)
                        .font(.display(13, weight: .bold))
                        .foregroundStyle(selected ? Color.brandInk : Color.textSecondary)
                        .frame(minWidth: 34, minHeight: 30)
                        .background {
                            if selected {
                                Capsule().fill(.brandGradient)
                                    .matchedGeometryEffect(id: "language", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.displayName)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.bgElevated))
        .overlay(Capsule().strokeBorder(Color.brandOrange.opacity(0.22), lineWidth: 1))
    }
}

/// Cycles System, Light and Dark, showing the icon of the mode in force.
struct ThemeToggle: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var loc: LocalizationManager

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                settings.theme = settings.theme.next
            }
        } label: {
            Image(systemName: settings.theme.symbolName)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(IconButtonStyle())
        .accessibilityLabel(loc.string(.settingsTheme))
        .accessibilityValue(loc.string(settings.theme.titleKey))
    }
}

/// Label plus monospaced value, the building block of the HUD and the
/// statistics screen.
struct StatRow: View {
    let label: String
    let value: String
    var highlighted = false

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.counter(17))
                .foregroundStyle(highlighted ? Color.brandOrange : Color.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Section heading used on Settings, Stats and How to play.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(Color.brandAmber)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Draws one tetromino, used by the hold slot, the next queue and the
/// decorative pieces on the menu.
struct PieceThumbnail: View {
    let type: TetrominoType
    var cellSize: CGFloat = 12
    var showGlyph = false

    private var cells: [Point] { type.cells(in: .spawn) }

    private var bounds: (minX: Int, minY: Int, width: Int, height: Int) {
        let xs = cells.map(\.x), ys = cells.map(\.y)
        return (xs.min() ?? 0, ys.min() ?? 0,
                (xs.max() ?? 0) - (xs.min() ?? 0) + 1,
                (ys.max() ?? 0) - (ys.min() ?? 0) + 1)
    }

    var body: some View {
        let box = bounds
        Canvas { context, _ in
            for cell in cells {
                let rect = CGRect(x: CGFloat(cell.x - box.minX) * cellSize,
                                  y: CGFloat(cell.y - box.minY) * cellSize,
                                  width: cellSize, height: cellSize)
                    .insetBy(dx: cellSize * 0.06, dy: cellSize * 0.06)
                let path = Path(roundedRect: rect, cornerRadius: cellSize * 0.2)
                context.fill(path, with: .color(Color.piece(type)))
                context.stroke(path, with: .color(.white.opacity(0.28)), lineWidth: 1)
            }
        }
        .frame(width: CGFloat(box.width) * cellSize,
               height: CGFloat(box.height) * cellSize)
        .overlay {
            if showGlyph {
                Text(type.accessibilityGlyph)
                    .font(.system(size: cellSize * 0.9, weight: .black, design: .rounded))
                    .foregroundStyle(.black.opacity(0.45))
            }
        }
    }
}
