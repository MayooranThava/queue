import SwiftUI

struct SettingsPlaceholderView: View {
    var body: some View {
        List {
            Section("Focus") {
                Label("Motivation preferences", systemImage: "heart")
                Label("Companion visibility", systemImage: "figure.mind.and.body")
                Label("Animation intensity", systemImage: "sparkles")
            }
            Section("Integrations") {
                Label("Calendar connections", systemImage: "calendar")
                Label("Notifications", systemImage: "bell")
            }
            Section("Privacy & data") {
                Label("Privacy", systemImage: "hand.raised")
                Label("Data management", systemImage: "externaldrive")
            }
            Section("About") {
                LabeledContent("Version", value: "0.1.0-phase1")
            }
        }
        .scrollContentBackground(.hidden)
        .background(QueueColors.background)
        .navigationTitle("Settings")
    }
}
