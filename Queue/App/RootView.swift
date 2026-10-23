import SwiftUI
import SwiftData
import QueueCore

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var services: AppServices
    @Query private var preferences: [UserPreferencesEntity]
    @AppStorage("showPlannedStartTimes") private var legacyShowPlannedStartTimes = false
    @State private var showOnboarding = false

    var body: some View {
        Group {
            if showOnboarding {
                OnboardingFlowView {
                    completeOnboarding()
                }
            } else {
                MainTabView()
            }
        }
        .background(QueueColors.background.ignoresSafeArea())
        .environment(\.queueCompanionVisible, preferences.first?.companionVisible ?? true)
        .environment(
            \.queueAnimationIntensity,
            AnimationIntensity.resolved(
                preferences.first?.animationIntensityRaw ?? AnimationIntensity.standard.rawValue
            )
        )
        .task {
            await services.configure(modelContext: modelContext)
            let prefs = UserPreferencesStore.entity(in: modelContext)
            adoptLegacyPlannedStartTimes(into: prefs)
            showOnboarding = !prefs.hasCompletedOnboarding
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await services.importWidgetEditsIfNeeded() }
        }
    }

    /// Copies the pre-Settings toolbar flag into the preferences row, then clears it.
    private func adoptLegacyPlannedStartTimes(into prefs: UserPreferencesEntity) {
        let decision = PlannedStartTimePreference.adopt(
            entityValue: prefs.showPlannedStartTimes,
            legacyValue: legacyShowPlannedStartTimes,
            entityExists: true
        )
        if prefs.showPlannedStartTimes != decision.entityValue {
            UserPreferencesSettingsEditor.setShowPlannedStartTimes(decision.entityValue, on: prefs)
            do {
                try modelContext.save()
            } catch {
                return
            }
        }
        if decision.clearLegacy {
            legacyShowPlannedStartTimes = false
        }
    }

    private func completeOnboarding() {
        if let prefs = preferences.first {
            prefs.hasCompletedOnboarding = true
            try? modelContext.save()
        }
        withAnimation(.easeInOut(duration: 0.35)) {
            showOnboarding = false
        }
    }
}
