import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var stats: StatsStore
    @Environment(\.dismiss) private var dismiss

    @State private var confirmingReset = false

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        appearanceSection
                        gameplaySection
                        controlsSection
                        audioSection
                        accessibilitySection
                        dangerSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle(loc.string(.settingsTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.string(.settingsDone)) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .alert(loc.string(.settingsResetStats), isPresented: $confirmingReset) {
                Button(loc.string(.settingsCancel), role: .cancel) {}
                Button(loc.string(.settingsReset), role: .destructive) { stats.reset() }
            } message: {
                Text(loc.string(.settingsResetStatsConfirm))
            }
        }
    }

    // MARK: Sections

    private var appearanceSection: some View {
        section(.settingsTheme) {
            HStack {
                Text(loc.string(.settingsLanguage))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                LanguageToggle()
            }

            Divider().overlay(Color.brandOrange.opacity(0.12))

            Picker(loc.string(.settingsTheme), selection: $settings.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Label(loc.string(theme.titleKey), systemImage: theme.symbolName)
                        .tag(theme)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var gameplaySection: some View {
        section(.settingsGameplay) {
            Toggle(loc.string(.settingsGhost), isOn: $settings.ghostEnabled)

            Divider().overlay(Color.brandOrange.opacity(0.12))

            slider(title: loc.string(.settingsDAS),
                   value: $settings.das,
                   range: SettingsStore.dasRange,
                   step: 0.001)

            slider(title: loc.string(.settingsARR),
                   value: $settings.arr,
                   range: SettingsStore.arrRange,
                   step: 0.001)
        }
    }

    private var controlsSection: some View {
        section(.settingsControls) {
            Toggle(loc.string(.settingsOnScreenButtons), isOn: $settings.onScreenButtons)

            if settings.onScreenButtons {
                Divider().overlay(Color.brandOrange.opacity(0.12))
                Picker(loc.string(.settingsHandedness), selection: $settings.handedness) {
                    ForEach(Handedness.allCases) { side in
                        Text(loc.string(side.titleKey)).tag(side)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: settings.onScreenButtons)
    }

    private var audioSection: some View {
        section(.settingsAudio) {
            Toggle(loc.string(.settingsMusic), isOn: $settings.musicEnabled)
            Divider().overlay(Color.brandOrange.opacity(0.12))
            Toggle(loc.string(.settingsSFX), isOn: $settings.sfxEnabled)
            Divider().overlay(Color.brandOrange.opacity(0.12))
            Toggle(loc.string(.settingsHaptics), isOn: $settings.hapticsEnabled)
        }
    }

    private var accessibilitySection: some View {
        section(.settingsAccessibility) {
            Toggle(loc.string(.settingsColorBlind), isOn: $settings.colorBlindMode)
            if settings.colorBlindMode {
                HStack(spacing: 10) {
                    ForEach(TetrominoType.allCases, id: \.self) { type in
                        PieceThumbnail(type: type, cellSize: 9, showGlyph: true)
                            .frame(height: 22)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: settings.colorBlindMode)
    }

    private var dangerSection: some View {
        Button(role: .destructive) {
            confirmingReset = true
        } label: {
            Text(loc.string(.settingsResetStats))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: Layout.minimumTapTarget)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .brandCard(cornerRadius: 16)
    }

    // MARK: Building blocks

    private func section<Content: View>(_ key: LocKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: loc.string(key))
            VStack(spacing: 12) { content() }
                .padding(Layout.cardPadding)
                .brandCard(cornerRadius: 18)
        }
        .tint(.brandOrange)
        .foregroundStyle(Color.textPrimary)
    }

    /// DAS and ARR are stored in seconds but read much better as
    /// milliseconds, so the label converts on the way out.
    private func slider(title: String,
                        value: Binding<Double>,
                        range: ClosedRange<Double>,
                        step: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(Int((value.wrappedValue * 1000).rounded())) ms")
                    .font(.counter(14))
                    .foregroundStyle(Color.brandAmber)
            }
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int((value.wrappedValue * 1000).rounded())) ms")
        }
    }
}
