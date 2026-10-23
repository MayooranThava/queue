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
    @State private var minutes: Int = Int(QueueTask.defaultEstimatedDuration / 60)
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
        _minutes = State(initialValue: max(1, Int((existing?.estimatedDuration ?? QueueTask.defaultEstimatedDuration) / 60)))
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
                    DurationEstimatePicker(minutes: $minutes)

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

// MARK: - Duration

enum DurationEstimate {
    static let presets = [10, 15, 20, 30]
    static let minimumMinutes = 5
    static let maximumMinutes = 180
    static let stepMinutes = 5

    static var defaultMinutes: Int {
        max(1, Int(QueueTask.defaultEstimatedDuration / 60))
    }
}

struct DurationEstimatePicker: View {
    @Binding var minutes: Int
    /// Onboarding has no form row, so the stepper gets the same card as before.
    var showsStepperChrome: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: QueueSpacing.sm) {
            DurationPresetChips(minutes: $minutes)

            Stepper(
                value: $minutes,
                in: DurationEstimate.minimumMinutes...DurationEstimate.maximumMinutes,
                step: DurationEstimate.stepMinutes
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(minutes) minutes")
                        .font(QueueTypography.headline(17))
                        .foregroundStyle(QueueColors.primaryText)
                    if !DurationEstimate.presets.contains(minutes) {
                        Text("Custom")
                            .font(QueueTypography.caption())
                            .foregroundStyle(QueueColors.secondaryText)
                    }
                }
            }
            .accessibilityLabel("Estimated duration, \(minutes) minutes")
            .padding(showsStepperChrome ? QueueSpacing.md : 0)
            .background {
                if showsStepperChrome {
                    RoundedRectangle(cornerRadius: QueueSpacing.cornerMinimal, style: .continuous)
                        .fill(QueueColors.secondarySurface.opacity(0.55))
                }
            }
        }
    }
}

struct DurationPresetChips: View {
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: QueueSpacing.xs) {
            ForEach(DurationEstimate.presets, id: \.self) { preset in
                let selected = minutes == preset
                Button {
                    minutes = preset
                } label: {
                    Text("\(preset) min")
                        .font(QueueTypography.caption())
                        .foregroundStyle(QueueColors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: QueueSpacing.minTouch)
                        .background(
                            RoundedRectangle(cornerRadius: QueueSpacing.cornerMinimal, style: .continuous)
                                .fill(
                                    selected
                                        ? QueueColors.secondarySurface
                                        : QueueColors.secondarySurface.opacity(0.35)
                                )
                        )
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(preset) minutes")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Duration presets")
    }
}
