import SwiftUI
import SwiftData

@main
struct QueueApp: App {
    private let container: ModelContainer
    @StateObject private var services: AppServices

    init() {
        // Install before the first scene so a tap on a focus alert is delivered on a cold launch.
        let services = AppServices()
        _services = StateObject(wrappedValue: services)
        container = AppModelContainer.make()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, .current)
                .environmentObject(services)
                .onOpenURL { url in
                    guard QueueDeepLink.matchesFocus(url) || QueueDeepLink.matchesQueue(url) else { return }
                    services.openFocus(taskID: QueueDeepLink.taskID(from: url))
                }
        }
        .modelContainer(container)
    }
}
