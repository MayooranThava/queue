import SwiftUI
import SwiftData
import QueueCore

struct OnboardingFlowView: View {
    var onFinished: () -> Void

    @Environment(\.modelContext) private var modelContext
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
            .background(QueueColors.background.ignoresSafeArea())
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
                .foregroundStyle(QueueColors.primaryText)
            Text("One task at a time.\nSmall tasks. Real progress.")
                .font(QueueTypography.headline(20))
                .foregroundStyle(QueueColors.secondaryText)
                .multilineTextAlignment(.center)
            CompanionAnimationView(state: .idle, reduceMotion: false)
                .frame(height: 160)
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
                .foregroundStyle(QueueColors.secondaryText)
            ForEach(MotivationProfile.allCases, id: \.self) { profile in
                Button {
                    selectedProfile = profile
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profileTitle(profile))
                                .font(QueueTypography.headline(17))
                                .foregroundStyle(QueueColors.primaryText)
                            Text(profileSubtitle(profile))
                                .font(QueueTypography.caption())
                                .foregroundStyle(QueueColors.secondaryText)
                        }
                        Spacer()
                        if selectedProfile == profile {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(QueueColors.sageDeep)
                        }
                    }
                    .padding(QueueSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: QueueSpacing.cornerMinimal, style: .continuous)
                            .fill(QueueColors.secondarySurface.opacity(selectedProfile == profile ? 0.9 : 0.45))
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
                .foregroundStyle(QueueColors.secondaryText)
            Spacer()
        }
        .padding(QueueSpacing.xl)
    }

    private var notifications: some View {
        VStack(alignment: .leading, spacing: QueueSpacing.lg) {
            Spacer()
            Text("Gentle reminders")
                .font(QueueTypography.title(32))
                .foregroundStyle(QueueColors.primaryText)
            Text("When a focus block ends, Queue can send an alert that names the task — even if your phone is locked. No guilt streaks.")
                .font(QueueTypography.body())
                .foregroundStyle(QueueColors.secondaryText)
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
                .foregroundStyle(QueueColors.secondaryText)
        case .authorized:
            Text("Focus alerts are on. Queue will ping you when the block ends.")
                .font(QueueTypography.caption())
                .foregroundStyle(QueueColors.secondaryText)
        case .denied:
            Text("Focus alerts are off. You can turn them on in iOS Settings. The timer still runs.")
                .font(QueueTypography.caption())
                .foregroundStyle(QueueColors.secondaryText)
        }
    }

    private var firstTask: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QueueSpacing.lg) {
                Spacer(minLength: QueueSpacing.xl)
                Text("Your first task")
                    .font(QueueTypography.title(32))
                    .foregroundStyle(QueueColors.primaryText)

                TextField("e.g. Outline the intro paragraph", text: $firstTaskTitle)
                    .textFieldStyle(QueueTextFieldStyle())
                    .submitLabel(.done)

                VStack(alignment: .leading, spacing: QueueSpacing.sm) {
                    Text("Time")
                        .font(QueueTypography.caption())
                        .foregroundStyle(QueueColors.secondaryText)
                    DurationEstimatePicker(minutes: $firstTaskMinutes, showsStepperChrome: true)
                }

                VStack(alignment: .leading, spacing: QueueSpacing.sm) {
                    Text("Difficulty")
                        .font(QueueTypography.caption())
                        .foregroundStyle(QueueColors.secondaryText)
                    HStack(spacing: QueueSpacing.xs) {
                        ForEach(TaskDifficulty.allCases, id: \.self) { value in
                            Button {
                                firstTaskDifficulty = value
                            } label: {
                                Text(value.displayName)
                                    .font(QueueTypography.caption())
                                    .foregroundStyle(QueueColors.primaryText)
                                    .frame(maxWidth: .infinity, minHeight: QueueSpacing.minTouch)
                                    .background(
                                        RoundedRectangle(cornerRadius: QueueSpacing.cornerMinimal, style: .continuous)
                                            .fill(
                                                firstTaskDifficulty == value
                                                    ? QueueColors.secondarySurface
                                                    : QueueColors.secondarySurface.opacity(0.35)
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
                    .foregroundStyle(QueueColors.secondaryText)

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
        persistPreferences()
        await createFirstTaskIfNeeded()
        services.analytics.track(.onboardingCompleted)
        onFinished()
    }

    private func persistPreferences() {
        let descriptor = FetchDescriptor<UserPreferencesEntity>()
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.motivationProfileRaw = selectedProfile.rawValue
            existing.hasCompletedOnboarding = true
        } else {
            let prefs = UserPreferencesEntity(motivationProfile: selectedProfile)
            prefs.hasCompletedOnboarding = true
            modelContext.insert(prefs)
        }
        try? modelContext.save()
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
                .fill(QueueColors.reward)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            Text(text)
                .font(QueueTypography.body())
                .foregroundStyle(QueueColors.primaryText)
        }
    }

    private func profileTitle(_ profile: MotivationProfile) -> String {
        switch profile {
        case .balanced: return "Balanced"
        case .speedRunner: return "Speed Runner"
        case .consistencyBuilder: return "Consistency Builder"
        }
    }

    private func profileSubtitle(_ profile: MotivationProfile) -> String {
        switch profile {
        case .balanced: return "Completion plus modest on-time bonuses."
        case .speedRunner: return "More emphasis on finishing within estimates."
        case .consistencyBuilder: return "Streaks and daily rhythm over speed."
        }
    }
}
