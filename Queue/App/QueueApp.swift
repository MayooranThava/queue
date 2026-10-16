import SwiftUI
import SwiftData

@main
struct QueueApp: App {
    private let container = AppModelContainer.make()
    @StateObject private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, .current)
                .environmentObject(services)
                .onOpenURL { url in
                    if QueueDeepLink.matchesFocus(url) || QueueDeepLink.matchesQueue(url) {
                        services.pendingOpenFocus = true
                    }
                }
        }
        .modelContainer(container)
    }
}
