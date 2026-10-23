import SwiftUI

struct MainTabView: View {
    @Environment(\.queueTheme) private var queueTheme
    @EnvironmentObject private var services: AppServices
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                QueueHomeView()
            }
            .tabItem {
                Label("Queue", systemImage: "list.bullet")
            }
            .tag(0)

            NavigationStack {
                CalendarPlaceholderView()
            }
            .tabItem {
                Label("Calendar", systemImage: "calendar")
            }
            .tag(1)

            NavigationStack {
                ProgressPlaceholderView()
            }
            .tabItem {
                Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
            }
            .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(3)
        }
        .onChange(of: services.pendingOpenFocus) { _, shouldOpen in
            if shouldOpen {
                selectedTab = 0
            }
        }
        .tint(QueueColors.primary)
        .toolbarBackground(QueueColors.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(QueueColors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .environment(\.queueTheme, queueTheme)
    }
}
