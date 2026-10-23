import SwiftUI
import SwiftData
import QueueCore

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.queueTheme) private var queueTheme
    @EnvironmentObject private var services: AppServices
    @Query private var preferences: [UserPreferencesEntity]
    @AppStorage("showPlannedStartTimes") private var legacyShowPlannedStartTimes = false
    @State private var showOnboarding = false
    @State private var uiTestReady = !QueueUITestLaunch.isActive

    var body: some View {
        Group {
            if !uiTestReady {
                Color.clear
            } else if showOnboarding {
                OnboardingFlowView {
                    completeOnboarding()
                }
            } else {
                MainTabView()
            }
        }
        .background(QueueColors.background)
        .environment(\.queueTheme, queueTheme)
        .environment(\.queueCompanionVisible, preferences.first?.companionVisible ?? true)
        .environment(
            \.queueAnimationIntensity,
            AnimationIntensity.resolved(
                preferences.first?.animationIntensityRaw ?? AnimationIntensity.standard.rawValue
            )
        )
        .task {
            if QueueUITestLaunch.isActive {
                prepareUITestStore()
            }
            await services.configure(modelContext: modelContext)
            let prefs = UserPreferencesStore.entity(in: modelContext)
            adoptLegacyPlannedStartTimes(into: prefs)
            showOnboarding = !prefs.hasCompletedOnboarding
            uiTestReady = true
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await services.importWidgetEditsIfNeeded() }
        }
    }

    /// Clears persisted rows, then optionally marks onboarding finished.
    /// Runs only when a UI test passed a launch argument.
    private func prepareUITestStore() {
        if QueueUITestLaunch.resetsStore {
            wipe(TaskEntity.self)
            wipe(FocusSessionEntity.self)
            wipe(XPTransactionEntity.self)
            wipe(UserPreferencesEntity.self)
            try? modelContext.save()
        }
        if QueueUITestLaunch.skipsOnboarding {
            let prefs = UserPreferencesStore.entity(in: modelContext)
            prefs.hasCompletedOnboarding = true
            try? modelContext.save()
        }
    }

    private func wipe<Model: PersistentModel>(_ type: Model.Type) {
        let rows = (try? modelContext.fetch(FetchDescriptor<Model>())) ?? []
        for row in rows {
            modelContext.delete(row)
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
