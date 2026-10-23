import SwiftUI
import SwiftData
import QueueCore

/// Saved preferences, the bundle version, and the system notification status.
///
/// Does not edit `autoStartNextTask`. That flag belongs to the Start next control.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.queueTheme) private var queueTheme
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var themes: QueueThemeSelection
    @Query private var preferences: [UserPreferencesEntity]
    @AppStorage("showPlannedStartTimes") private var legacyShowPlannedStartTimes = false
    @ScaledMetric(relativeTo: .body) private var swatchSize: CGFloat = 12
    @State private var notificationAuthorization: FocusNotificationAuthorization?

    var body: some View {
        List {
            companionSection
            themeSection
            motivationSection
            tasksSection
            notificationsSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(QueueColors.background)
        .environment(\.queueTheme, queueTheme)
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
            .settingsRow(separator: separatorColor)

            Picker(selection: animationBinding) {
                ForEach(AnimationIntensity.allCases) { intensity in
                    Text(intensity.displayName).tag(intensity)
                }
            } label: {
                Text("Animation")
                    .foregroundStyle(QueueColors.textPrimary)
            }
            .accessibilityHint(animationBinding.wrappedValue.summary)
            .settingsRow(separator: separatorColor)
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
            .settingsRow(separator: separatorColor)
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
            .settingsRow(separator: separatorColor)

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
            .settingsRow(separator: separatorColor)
        } header: {
            settingsHeader("Tasks")
        } footer: {
            settingsFooter("Start times replace durations on upcoming tasks. The daily goal is how many tasks count as a full day.")
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
            .settingsRow(separator: separatorColor)
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
            .settingsRow(separator: separatorColor)
        } header: {
            settingsHeader("About")
        }
    }

    private var themeSection: some View {
        Section {
            ForEach(QueueTheme.all) { theme in
                Button {
                    themes.select(theme)
                } label: {
                    themeRow(theme)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(themeAccessibilityLabel(theme))
                .accessibilityHint(theme.isPro ? "Pro theme. Unlocked." : "Free theme.")
                .accessibilityAddTraits(.isButton)
                .settingsRow(separator: separatorColor)
            }
        } header: {
            settingsHeader("Theme")
        } footer: {
            settingsFooter("Used in the app, widgets, and Live Activity. Pro themes stay unlocked until a Pro tier exists.")
        }
    }

    private func themeRow(_ theme: QueueTheme) -> some View {
        let palette = colorScheme == .dark ? theme.dark : theme.light
        let selected = themes.theme.id == theme.id
        return HStack(spacing: QueueSpacing.sm) {
            HStack(spacing: 3) {
                swatch(palette.primary)
                swatch(palette.accent)
                swatch(palette.success)
                swatch(palette.danger)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(palette.background), in: Capsule())
            .accessibilityHidden(true)

            Text(theme.name)
                .font(.body)
                .foregroundStyle(QueueColors.textPrimary)
            Spacer(minLength: QueueSpacing.sm)
            if theme.isPro {
                Text("Pro")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(QueueColors.onPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(QueueColors.primary, in: Capsule())
                    .accessibilityHidden(true)
            }
            if selected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(QueueColors.primary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: QueueSpacing.minTouch)
    }

    private func swatch(_ rgb: QueueRGB) -> some View {
        Circle()
            .fill(Color(rgb))
            .frame(width: swatchSize, height: swatchSize)
    }

    private func themeAccessibilityLabel(_ theme: QueueTheme) -> String {
        if themes.theme.id == theme.id {
            return "\(theme.name) theme, selected"
        }
        return "\(theme.name) theme"
    }

    private var separatorColor: Color {
        QueueColors.concrete(
            .textSecondary,
            theme: themes.theme,
            scheme: colorScheme,
            increasedContrast: contrast == .increased
        )
        .opacity(0.25)
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
    func settingsRow(separator: Color) -> some View {
        listRowBackground(Rectangle().fill(QueueColors.surface))
            .listRowSeparatorTint(separator)
    }
}
