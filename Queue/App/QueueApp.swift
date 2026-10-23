import SwiftUI
import SwiftData

@main
struct QueueApp: App {
    @State private var storeLaunch: AppModelContainer.OpenResult
    @StateObject private var services: AppServices

    init() {
        // Install before the first scene so a tap on a focus alert is delivered on a cold launch.
        let services = AppServices()
        _services = StateObject(wrappedValue: services)
        _storeLaunch = State(initialValue: AppModelContainer.open())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch storeLaunch {
                case .ready(let container):
                    RootView()
                        .environmentObject(services)
                        .modelContainer(container)
                case .failed(let error):
                    PersistenceFailureView(error: error) {
                        storeLaunch = AppModelContainer.open()
                    }
                }
            }
            .environment(\.locale, .current)
            .onOpenURL(perform: handleOpenURL)
        }
    }

    private func handleOpenURL(_ url: URL) {
        guard QueueDeepLink.matchesFocus(url) || QueueDeepLink.matchesQueue(url) else { return }
        services.openFocus(taskID: QueueDeepLink.taskID(from: url))
    }
}
