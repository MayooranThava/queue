import SwiftUI
import QueueCore

struct AddEditTaskView: View {
    @Environment(\.dismiss) private var dismiss

    let existing: QueueTask?
    let onSave: (String, String?, TimeInterval) async -> Void

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var minutes: Int = 25
    @State private var isSaving = false
    @FocusState private var titleFocused: Bool

    init(
        existing: QueueTask? = nil,
        onSave: @escaping (String, String?, TimeInterval) async -> Void
    ) {
        self.existing = existing
        self.onSave = onSave
        _title = State(initialValue: existing?.title ?? "")
        _notes = State(initialValue: existing?.notes ?? "")
        _minutes = State(initialValue: max(1, Int((existing?.estimatedDuration ?? 1500) / 60)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What will you finish?", text: $title)
                        .focused($titleFocused)
                        .font(QueueTypography.body())
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Task")
                } footer: {
                    Text("Keep it small enough to start now.")
                        .foregroundStyle(QueueColors.secondaryText)
                }

                Section("Estimate") {
                    Stepper(value: $minutes, in: 5...180, step: 5) {
                        Text("\(minutes) minutes")
                            .font(QueueTypography.headline(17))
                    }
                    .accessibilityLabel("Estimated duration, \(minutes) minutes")
                }
            }
            .scrollContentBackground(.hidden)
            .background(QueueColors.background)
            .navigationTitle(existing == nil ? "New task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear { titleFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        await onSave(
            title,
            trimmedNotes.isEmpty ? nil : trimmedNotes,
            TimeInterval(minutes * 60)
        )
        isSaving = false
        dismiss()
    }
}
