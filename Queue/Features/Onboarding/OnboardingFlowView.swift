import SwiftUI
import SwiftData
import QueueCore

struct OnboardingFlowView: View {
    var onFinished: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.queueCompanionVisible) private var companionVisible
    @Environment(\.queueTheme) private var queueTheme
    @EnvironmentObject private var services: AppServices
    @State private var step = 0
    @State private var selectedProfile: MotivationProfile = .balanced
    @State private var firstTaskTitle = ""
    @State private var firstTaskMinutes = DurationEstimate.defaultMinutes
    @State private var firstTaskDifficulty: TaskDifficulty = .medium
    @State private var notificationAuthorization: FocusNotificationAuthorization = .notDetermined

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $step) {
                    welcome.tag(0)
                    explanation.tag(1)
                    motivation.tag(2)
                    calendarOptional.tag(3)
                    notifications.tag(4)
                    firstTask.tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.35), value: step)

                bottomBar
                    .padding(QueueSpacing.lg)
            }
            .background(QueueColors.background)
            .environment(\.queueTheme, queueTheme)
            .navigationBarHidden(true)
        }
        .onAppear {
            services.analytics.track(.onboardingStarted)
        }
        .task {
            await services.configure(modelContext: modelContext)
        }
        .onChange(of: step) { _, newStep in
            guard newStep == 4 else { return }
            Task { await refreshNotificationAuthorization() }
        }
    }

    private var welcome: some View {
        VStack(spacing: QueueSpacing.lg) {
            Spacer()
            Text("Queue")
                .font(QueueTypography.display(48))
                .foregroundStyle(QueueColors.textPrimary)
            Text("One task at a time.\nSmall tasks. Real progress.")
                .font(QueueTypography.headline(20))
                .foregroundStyle(QueueColors.textSecondary)
                .multilineTextAlignment(.center)
            if companionVisible {
                CompanionAnimationView(state: .idle, reduceMotion: false)
                    .frame(height: 160)
            }
            Spacer()
        }
        .padding(QueueSpacing.xl)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: QueueSpacing.lg) {
            Spacer()
            Text("How it works")
                .font(QueueTypography.title(32))
            bullet("Line up small tasks in a simple queue.")
            bullet("Focus on the one at the front.")
            bullet("Finish, celebrate, then move forward.")
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(QueueSpacing.xl)
    }

    private var motivation: some View {
        VStack(alignment: .leading, spacing: QueueSpacing.md) {
            Spacer()
            Text("Motivation style")
                .font(QueueTypography.title(32))
            Text("You can change this later in Settings.")
                .font(QueueTypography.body())
                .foregroundStyle(QueueColors.textSecondary)
            ForEach(MotivationProfile.allCases, id: \.self) { profile in
                Button {
                    selectedProfile = profile
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.displayName)
                                .font(QueueTypography.headline(17))
                                .foregroundStyle(QueueColors.textPrimary)
                            Text(profile.summary)
                                .font(QueueTypography.caption())
                                .foregroundStyle(QueueColors.textSecondary)
                        }
                        Spacer()
                        if selectedProfile == profile {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(QueueColors.success)
                        }
                    }
                    .padding(QueueSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: QueueSpacing.cornerMinimal, style: .continuous)
                            .fill(QueueColors.surface.opacity(selectedProfile == profile ? 0.9 : 0.45))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedProfile == profile ? .isSelected : [])
            }
            Spacer()
        }
        .padding(QueueSpacing.xl)
    }

    private var calendarOptional: some View {
        VStack(alignment: .leading, spacing: QueueSpacing.lg) {
            Spacer()
            Text("Calendar later")
                .font(QueueTypography.title(32))
            Text("Connect Apple Calendar or Outlook when you want Smart Gaps. Queue works fully offline without it.")
                .font(QueueTypography.body())
                .foregroundStyle(QueueColors.textSecondary)
            Spacer()
        }
        .padding(QueueSpacing.xl)
    }

    private var notifications: some View {
        VStack(alignment: .leading, spacing: QueueSpacing.lg) {
            Spacer()
            Text("Gentle reminders")
                .font(QueueTypography.title(32))
                .foregroundStyle(QueueColors.textPrimary)
            Text("When a focus block ends, Queue can send an alert that names the task — even if your phone is locked. No guilt streaks.")
                .font(QueueTypography.body())
                .foregroundStyle(QueueColors.textSecondary)
            notificationStatusCopy
            if notificationAuthorization == .notDetermined {
                Button("Allow focus alerts") {
                    Task { await allowFocusAlerts() }
                }
                .buttonStyle(QueueSecondaryButtonStyle())
            }
            Spacer()
        }
        .padding(QueueSpacing.xl)
    }

    @ViewBuilder
    private var notificationStatusCopy: some View {
        switch notificationAuthorization {
        case .notDetermined:
            Text("You can allow alerts now, or Queue will ask the first time a focus timer starts.")
                .font(QueueTypography.caption())
                .foregroundStyle(QueueColors.textSecondary)
        case .authorized:
            Text("Focus alerts are on. Queue will ping you when the block ends.")
                .font(QueueTypography.caption())
                .foregroundStyle(QueueColors.textSecondary)
        case .denied:
            Text("Focus alerts are off. You can turn them on in iOS Settings. The timer still runs.")
                .font(QueueTypography.caption())
                .foregroundStyle(QueueColors.textSecondary)
        }
    }

    private var firstTask: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QueueSpacing.lg) {
                Spacer(minLength: QueueSpacing.xl)
                Text("Your first task")
                    .font(QueueTypography.title(32))
                    .foregroundStyle(QueueColors.textPrimary)

                TextField("e.g. Outline the intro paragraph", text: $firstTaskTitle)
                    .textFieldStyle(QueueTextFieldStyle())
                    .submitLabel(.done)
                    .accessibilityIdentifier(QueueAccessibilityID.onboardingTaskTitle)

                VStack(alignment: .leading, spacing: QueueSpacing.sm) {
                    Text("Time")
                        .font(QueueTypography.caption())
                        .foregroundStyle(QueueColors.textSecondary)
                    DurationEstimatePicker(minutes: $firstTaskMinutes, showsStepperChrome: true)
                }

                VStack(alignment: .leading, spacing: QueueSpacing.sm) {
                    Text("Difficulty")
                        .font(QueueTypography.caption())
                        .foregroundStyle(QueueColors.textSecondary)
                    HStack(spacing: QueueSpacing.xs) {
                        ForEach(TaskDifficulty.allCases, id: \.self) { value in
                            Button {
                                firstTaskDifficulty = value
                            } label: {
                                Text(value.displayName)
                                    .font(QueueTypography.caption())
                                    .foregroundStyle(QueueColors.textPrimary)
                                    .frame(maxWidth: .infinity, minHeight: QueueSpacing.minTouch)
                                    .background(
                                        RoundedRectangle(cornerRadius: QueueSpacing.cornerMinimal, style: .continuous)
                                            .fill(
                                                firstTaskDifficulty == value
                                                    ? QueueColors.surface
                                                    : QueueColors.surface.opacity(0.35)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(firstTaskDifficulty == value ? .isSelected : [])
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityHint("Affects XP reward, not the timer length")
                }

                Text("Start tiny. Momentum beats perfection.")
                    .font(QueueTypography.caption())
                    .foregroundStyle(QueueColors.textSecondary)

                Spacer(minLength: QueueSpacing.xl)
            }
            .padding(QueueSpacing.xl)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: QueueSpacing.md) {
            if step > 0 {
                Button("Back") {
                    step -= 1
                }
                .buttonStyle(QueueSecondaryButtonStyle())
            }
            Button(step == 5 ? "Start Queue" : "Continue") {
                Task { await advance() }
            }
            .buttonStyle(QueuePrimaryButtonStyle())
            .disabled(step == 5 && firstTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier(QueueAccessibilityID.onboardingContinue)
        }
    }

    private func refreshNotificationAuthorization() async {
        notificationAuthorization = await services.focusAlertCenter.authorizationStatus()
    }

    private func allowFocusAlerts() async {
        let current = await services.focusAlertCenter.authorizationStatus()
        guard FocusNotificationPermissionPolicy.shouldRequest(status: current, reason: .onboardingOptIn) else {
            notificationAuthorization = current
            return
        }
        notificationAuthorization = await services.focusAlertCenter.requestAuthorization()
    }

    private func advance() async {
        if step < 5 {
            step += 1
            return
        }
        await persistPreferences()
        await createFirstTaskIfNeeded()
        services.analytics.track(.onboardingCompleted)
        onFinished()
    }

    private func persistPreferences() async {
        let descriptor = FetchDescriptor<UserPreferencesEntity>()
        if let existing = try? modelContext.fetch(descriptor).first {
            UserPreferencesSettingsEditor.setMotivationProfile(selectedProfile, on: existing)
            existing.hasCompletedOnboarding = true
        } else {
            let prefs = UserPreferencesEntity(motivationProfile: selectedProfile)
            prefs.hasCompletedOnboarding = true
            modelContext.insert(prefs)
        }
        try? modelContext.save()
        await services.rewardEngine.setProfile(selectedProfile)
    }

    private func createFirstTaskIfNeeded() async {
        let title = firstTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        await services.configure(modelContext: modelContext)
        _ = try? await services.taskRepository?.create(
            title: title,
            notes: nil,
            estimatedDuration: TimeInterval(firstTaskMinutes * 60),
            difficulty: firstTaskDifficulty
        )
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: QueueSpacing.sm) {
            Circle()
                .fill(QueueColors.rewardMark)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            Text(text)
                .font(QueueTypography.body())
                .foregroundStyle(QueueColors.textPrimary)
        }
    }

}
