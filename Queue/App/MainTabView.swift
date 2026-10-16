import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                QueueHomeView()
            }
            .tabItem {
                Label("Queue", systemImage: "list.bullet")
            }

            NavigationStack {
                CalendarPlaceholderView()
            }
            .tabItem {
                Label("Calendar", systemImage: "calendar")
            }

            NavigationStack {
                ProgressPlaceholderView()
            }
            .tabItem {
                Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
            }

            NavigationStack {
                SettingsPlaceholderView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .tint(QueueColors.sageDeep)
    }
}
