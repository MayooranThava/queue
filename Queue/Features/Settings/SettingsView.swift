import SwiftUI
import SwiftData
import QueueCore

/// Saved preferences, the bundle version, and the system notification status.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var services: AppServices
    @Query private var preferences: [UserPreferencesEntity]
    @AppStorage("showPlannedStartTimes") private var legacyShowPlannedStartTimes = false
    @State private var notificationAuthorization: FocusNotificationAuthorization?

    var body: some View {
        List {
            companionSection
            motivationSection
            tasksSection
            notificationsSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(QueueColors.background.ignoresSafeArea())
        .tint(QueueColors.primary)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .task { await refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshNotificationStatus() }
        }
    }

    private var companionSection: some View {
        Section {
            Toggle(isOn: companionBinding) {
                Text("Show companion")
                    .foregroundStyle(QueueColors.textPrimary)
            }
            .accessibilityHint("Hides the companion on Queue, Focus, and celebrations.")
            .settingsRow()

            Picker(selection: animationBinding) {
                ForEach(AnimationIntensity.allCases) { intensity in
                    Text(intensity.displayName).tag(intensity)
                }
            } label: {
                Text("Animation")
                    .foregroundStyle(QueueColors.textPrimary)
            }
            .accessibilityHint(animationBinding.wrappedValue.summary)
            .settingsRow()
        } header: {
            settingsHeader("Companion")
        } footer: {
            settingsFooter("Turn the companion off to hide it. Reduced animation holds it still.")
        }
    }

    private var motivationSection: some View {
        Section {
            Picker(selection: motivationBinding) {
                ForEach(MotivationProfile.allCases, id: \.self) { profile in
                    Text(profile.displayName).tag(profile)
                }
            } label: {
                Text("Motivation")
                    .foregroundStyle(QueueColors.textPrimary)
            }
            .accessibilityHint(motivationBinding.wrappedValue.summary)
            .settingsRow()
        } header: {
            settingsHeader("Motivation")
        } footer: {
            settingsFooter(motivationBinding.wrappedValue.summary)
        }
    }

    private var tasksSection: some View {
        Section {
            Toggle(isOn: plannedStartTimesBinding) {
                Text("Show planned start times")
                    .foregroundStyle(QueueColors.textPrimary)
            }
            .accessibilityHint("Shows a projected start on upcoming tasks.")
            .settingsRow()

            Toggle(isOn: autoStartBinding) {
                Text("Start the next task")
                    .foregroundStyle(QueueColors.textPrimary)
            }
            .accessibilityHint("After a celebration, the following task starts on its own. You can cancel the countdown.")
            .settingsRow()

            Stepper(value: dailyGoalBinding, in: DailyGoalCount.range) {
                LabeledContent {
                    Text(DailyGoalCount.label(for: dailyGoalBinding.wrappedValue))
                        .foregroundStyle(QueueColors.textSecondary)
                } label: {
                    Text("Daily goal")
                        .foregroundStyle(QueueColors.textPrimary)
                }
            }
            .accessibilityHint("How many finished tasks count as a full day.")
            .settingsRow()
        } header: {
            settingsHeader("Tasks")
        } footer: {
            settingsFooter("Start times replace durations on upcoming tasks. The daily goal is how many tasks count as a full day. With Start the next task on, the following block begins after a short countdown you can cancel.")
        }
    }

    private var notificationsSection: some View {
        Section {
            Button {
                AppSettingsLink.open()
            } label: {
                HStack(spacing: QueueSpacing.sm) {
                    Text("Notifications")
                        .foregroundStyle(QueueColors.textPrimary)
                    Spacer(minLength: QueueSpacing.sm)
                    Text(notificationStatusLabel)
                        .foregroundStyle(QueueColors.textSecondary)
                    Image(systemName: "arrow.up.forward")
                        .font(.footnote)
                        .foregroundStyle(QueueColors.textSecondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: QueueSpacing.minTouch)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Queue in iOS Settings")
            .settingsRow()
        } header: {
            settingsHeader("Notifications")
        } footer: {
            settingsFooter("Shows whether iOS allows Queue alerts, and opens Queue in iOS Settings.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent {
                Text(versionText)
                    .foregroundStyle(QueueColors.textSecondary)
            } label: {
                Text("Version")
                    .foregroundStyle(QueueColors.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .settingsRow()
        } header: {
            settingsHeader("About")
        }
    }

    private var companionBinding: Binding<Bool> {
        Binding(
            get: { preferences.first?.companionVisible ?? true },
            set: { newValue in
                update { UserPreferencesSettingsEditor.setCompanionVisible(newValue, on: $0) }
            }
        )
    }

    private var animationBinding: Binding<AnimationIntensity> {
        Binding(
            get: {
                AnimationIntensity.resolved(
                    preferences.first?.animationIntensityRaw ?? AnimationIntensity.standard.rawValue
                )
            },
            set: { newValue in
                update { UserPreferencesSettingsEditor.setAnimationIntensity(newValue, on: $0) }
            }
        )
    }

    private var motivationBinding: Binding<MotivationProfile> {
        Binding(
            get: { preferences.first?.motivationProfile ?? .balanced },
            set: { newValue in
                update { UserPreferencesSettingsEditor.setMotivationProfile(newValue, on: $0) }
                Task { await services.rewardEngine.setProfile(newValue) }
            }
        )
    }

    private var plannedStartTimesBinding: Binding<Bool> {
        Binding(
            get: { preferences.first?.showPlannedStartTimes ?? false },
            set: { newValue in
                legacyShowPlannedStartTimes = newValue
                update { UserPreferencesSettingsEditor.setShowPlannedStartTimes(newValue, on: $0) }
            }
        )
    }

    private var autoStartBinding: Binding<Bool> {
        Binding(
            get: { preferences.first?.autoStartNextTask ?? false },
            set: { newValue in
                update { UserPreferencesSettingsEditor.setAutoStartNextTask(newValue, on: $0) }
            }
        )
    }

    private var dailyGoalBinding: Binding<Int> {
        Binding(
            get: { DailyGoalCount.clamped(preferences.first?.dailyGoalCount ?? 3) },
            set: { newValue in
                update { UserPreferencesSettingsEditor.setDailyGoalCount(newValue, on: $0) }
            }
        )
    }

    private var notificationStatusLabel: String {
        guard let notificationAuthorization else { return "Checking" }
        return NotificationSettingsStatus.label(for: notificationAuthorization)
    }

    private var versionText: String {
        AppVersionFormatting.display(in: .main)
    }

    private func settingsHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(QueueColors.textSecondary)
            .textCase(nil)
    }

    private func settingsFooter(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(QueueColors.textSecondary)
    }

    private func update(_ change: (UserPreferencesEntity) -> Void) {
        let prefs = UserPreferencesStore.entity(in: modelContext)
        change(prefs)
        try? modelContext.save()
    }

    private func refreshNotificationStatus() async {
        notificationAuthorization = await services.focusAlertCenter.authorizationStatus()
    }
}

private extension View {
    func settingsRow() -> some View {
        listRowBackground(QueueColors.surface)
            .listRowSeparatorTint(QueueColors.textSecondary.opacity(0.25))
    }
}
