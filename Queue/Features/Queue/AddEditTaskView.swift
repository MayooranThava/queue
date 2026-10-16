import SwiftUI
import QueueCore

struct TaskDraft: Equatable {
    var title: String
    var notes: String?
    var estimatedDuration: TimeInterval
    var difficulty: TaskDifficulty
    var plannedStartAt: Date?
}

struct AddEditTaskView: View {
    @Environment(\.dismiss) private var dismiss

    let existing: QueueTask?
    let onSave: (TaskDraft) async -> Void

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var minutes: Int = 25
    @State private var difficulty: TaskDifficulty = .medium
    @State private var hasPlannedStart = false
    @State private var plannedStartAt: Date = Date()
    @State private var isSaving = false
    @FocusState private var titleFocused: Bool

    init(
        existing: QueueTask? = nil,
        onSave: @escaping (TaskDraft) async -> Void
    ) {
        self.existing = existing
        self.onSave = onSave
        _title = State(initialValue: existing?.title ?? "")
        _notes = State(initialValue: existing?.notes ?? "")
        _minutes = State(initialValue: max(1, Int((existing?.estimatedDuration ?? 1500) / 60)))
        _difficulty = State(initialValue: existing?.difficulty ?? .medium)
        _hasPlannedStart = State(initialValue: existing?.plannedStartAt != nil)
        _plannedStartAt = State(initialValue: existing?.plannedStartAt ?? Date())
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

                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(TaskDifficulty.allCases, id: \.self) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    .accessibilityHint("Affects XP reward, not the timer length")
                }

                Section {
                    Toggle("Preferred start time", isOn: $hasPlannedStart)
                    if hasPlannedStart {
                        DatePicker(
                            "Start at",
                            selection: $plannedStartAt,
                            displayedComponents: [.hourAndMinute]
                        )
                    }
                } header: {
                    Text("Schedule (optional)")
                } footer: {
                    Text("Shown in Up next when “Show start times” is on. Estimates still drive the focus timer.")
                        .foregroundStyle(QueueColors.secondaryText)
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
        let draft = TaskDraft(
            title: title,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            estimatedDuration: TimeInterval(minutes * 60),
            difficulty: difficulty,
            plannedStartAt: hasPlannedStart ? plannedStartAt : nil
        )
        await onSave(draft)
        isSaving = false
        dismiss()
    }
}
