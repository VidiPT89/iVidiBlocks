import SwiftUI

struct PauseOverlay: View {
    let onResume: () -> Void
    let onRestart: () -> Void
    let onQuit: () -> Void

    @EnvironmentObject private var loc: LocalizationManager
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onResume)

            VStack(spacing: 18) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.brandGradient)

                Text(loc.string(.pauseTitle))
                    .font(.display(28))
                    .foregroundStyle(Color.textPrimary)

                VStack(spacing: 10) {
                    Button(loc.string(.pauseResume), action: onResume)
                        .buttonStyle(BrandButtonStyle())
                    Button(loc.string(.pauseRestart), action: onRestart)
                        .buttonStyle(BrandButtonStyle(prominent: false))
                    Button(loc.string(.pauseQuit), action: onQuit)
                        .buttonStyle(BrandButtonStyle(prominent: false))
                }

                HStack(spacing: 12) {
                    LanguageToggle()
                    ThemeToggle()
                }
                .padding(.top, 2)
            }
            .padding(26)
            .frame(maxWidth: 320)
            .brandCard(cornerRadius: 26)
            .scaleEffect(appeared ? 1 : 0.92)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { appeared = true }
        }
    }
}
