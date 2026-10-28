import SwiftUI

/// The list of guided drills, opened from the menu.
struct PracticeView: View {
    let onStart: (Lesson) -> Void

    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var stats: StatsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(loc.string(.practiceIntro))
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 4)

                        ForEach(Array(Lesson.all.enumerated()), id: \.element.id) { index, lesson in
                            lessonRow(lesson, number: index + 1)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(loc.string(.practiceTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.string(.commonClose)) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func lessonRow(_ lesson: Lesson, number: Int) -> some View {
        let done = stats.completedLessons.contains(lesson.id)
        return Button {
            dismiss()
            onStart(lesson)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(done ? AnyShapeStyle(.brandGradient) : AnyShapeStyle(Color.bgSecondary))
                        .frame(width: 36, height: 36)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(Color.brandInk)
                    } else {
                        Text("\(number)")
                            .font(.counter(15))
                            .foregroundStyle(Color.brandAmber)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(loc.string(lesson.titleKey))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.textPrimary)
                    Text(loc.string(lesson.instructionKey))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .brandCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? loc.string(.practiceDone) : "")
    }
}

/// What to do in the current drill, shown above the board.
struct LessonBriefing: View {
    let lesson: Lesson

    @EnvironmentObject private var loc: LocalizationManager

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.brandAmber)
            Text(loc.string(lesson.instructionKey))
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .brandCard(cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }
}

/// Passed or failed card at the end of a drill attempt.
struct LessonResultView: View {
    let lesson: Lesson
    let passed: Bool
    let onRetry: () -> Void
    let onNext: () -> Void
    let onExit: () -> Void

    @EnvironmentObject private var loc: LocalizationManager
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: passed ? "checkmark.seal.fill" : "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.brandGradient)

                Text(loc.string(passed ? .practicePassed : .practiceFailed))
                    .font(.display(26))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text(loc.string(lesson.titleKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandAmber)

                VStack(spacing: 10) {
                    if passed, lesson.next != nil {
                        Button(loc.string(.practiceNext), action: onNext)
                            .buttonStyle(BrandButtonStyle())
                        Button(loc.string(.practiceRetry), action: onRetry)
                            .buttonStyle(BrandButtonStyle(prominent: false))
                    } else {
                        Button(loc.string(.practiceRetry), action: onRetry)
                            .buttonStyle(BrandButtonStyle(prominent: !passed))
                    }
                    Button(loc.string(.gameOverMenu), action: onExit)
                        .buttonStyle(BrandButtonStyle(prominent: false))
                }
            }
            .padding(26)
            .frame(maxWidth: 340)
            .brandCard(cornerRadius: 26)
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { appeared = true }
        }
    }
}
