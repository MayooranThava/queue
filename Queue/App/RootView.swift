import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var services: AppServices
    @Query private var preferences: [UserPreferencesEntity]
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
        .task {
            await services.configure(modelContext: modelContext)
            ensurePreferences()
            showOnboarding = !(preferences.first?.hasCompletedOnboarding ?? false)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await services.importWidgetEditsIfNeeded() }
        }
    }

    private func ensurePreferences() {
        guard preferences.isEmpty else { return }
        modelContext.insert(UserPreferencesEntity())
        try? modelContext.save()
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
