import SwiftUI
import SwiftData
import QueueCore

struct QueueHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var services: AppServices
    @Query(sort: [
        SortDescriptor(\TaskEntity.queuePosition),
        SortDescriptor(\TaskEntity.createdAt)
    ]) private var taskEntities: [TaskEntity]

    @State private var showAddTask = false
    @State private var editingTask: QueueTask?
    @State private var focusTask: QueueTask?
    @State private var errorMessage: String?
    @State private var undoTaskTitle: String?

    private var activeTasks: [QueueTask] {
        taskEntities
            .map { $0.asDomain() }
            .filter(\.isInActiveQueue)
            .sorted { $0.queuePosition < $1.queuePosition }
    }

    private var headTask: QueueTask? { activeTasks.first }
    private var upcoming: [QueueTask] {
        Array(activeTasks.dropFirst())
    }

    var body: some View {
        ZStack {
            QueueColors.background.ignoresSafeArea()

            Group {
                if activeTasks.isEmpty {
                    emptyState
                } else {
                    populatedState
                }
            }
        }
        .navigationTitle("Queue")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddTask = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: QueueSpacing.minTouch, height: QueueSpacing.minTouch)
                }
                .accessibilityLabel("Add task")
            }
        }
        .sheet(isPresented: $showAddTask) {
            AddEditTaskView { title, notes, duration in
                await createTask(title: title, notes: notes, duration: duration)
            }
        }
        .sheet(item: $editingTask) { task in
            AddEditTaskView(existing: task) { title, notes, duration in
                await updateTask(task, title: title, notes: notes, duration: duration)
            }
        }
        .fullScreenCover(item: $focusTask) { task in
            FocusPlaceholderView(task: task)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await services.configure(modelContext: modelContext)
        }
        .safeAreaInset(edge: .bottom) {
            if let undoTaskTitle {
                undoBanner(title: undoTaskTitle)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: QueueSpacing.lg) {
            Spacer()
            CompanionAnimationView(state: .idle, reduceMotion: false)
                .frame(height: 140)
                .accessibilityHidden(true)
            Text("Nothing in your queue")
                .font(QueueTypography.title(28))
                .foregroundStyle(QueueColors.primaryText)
            Text("Add one small task. Focus on that alone.")
                .font(QueueTypography.body())
                .foregroundStyle(QueueColors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, QueueSpacing.xl)
            Button("Add your first task") {
                showAddTask = true
            }
            .buttonStyle(QueuePrimaryButtonStyle())
            .padding(.horizontal, QueueSpacing.xl)
            Spacer()
        }
        .accessibilityElement(children: .contain)
    }

    private var populatedState: some View {
        List {
            if let headTask {
                Section {
                    ActiveTaskHero(
                        task: headTask,
                        onEdit: { editingTask = headTask },
                        onFocus: { focusTask = headTask }
                    )
                    .listRowInsets(EdgeInsets(
                        top: QueueSpacing.md,
                        leading: QueueSpacing.md,
                        bottom: QueueSpacing.md,
                        trailing: QueueSpacing.md
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } header: {
                    Text("Now")
                        .font(QueueTypography.caption())
                        .foregroundStyle(QueueColors.secondaryText)
                        .textCase(nil)
                }
            }

            if !upcoming.isEmpty {
                Section {
                    ForEach(upcoming) { task in
                        UpcomingTaskRow(task: task)
                            .contentShape(Rectangle())
                            .onTapGesture { editingTask = task }
                            .listRowInsets(EdgeInsets(
                                top: QueueSpacing.sm,
                                leading: QueueSpacing.md,
                                bottom: QueueSpacing.sm,
                                trailing: QueueSpacing.md
                            ))
                            .listRowBackground(QueueColors.secondarySurface.opacity(0.35))
                    }
                    .onMove(perform: moveUpcoming)
                } header: {
                    Text("Up next")
                        .font(QueueTypography.caption())
                        .foregroundStyle(QueueColors.secondaryText)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
    }

    private func undoBanner(title: String) -> some View {
        HStack {
            Text("Completed “\(title)”")
                .font(QueueTypography.body(15))
                .foregroundStyle(QueueColors.primaryText)
            Spacer()
            Button("Undo") {
                Task { await undoCompletion() }
            }
            .font(QueueTypography.headline(15))
        }
        .padding(QueueSpacing.md)
        .background(.ultraThinMaterial)
        .padding(.horizontal, QueueSpacing.md)
        .padding(.bottom, QueueSpacing.sm)
    }

    private func createTask(title: String, notes: String?, duration: TimeInterval) async {
        do {
            _ = try await services.taskRepository?.create(
                title: title,
                notes: notes,
                estimatedDuration: duration
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateTask(
        _ task: QueueTask,
        title: String,
        notes: String?,
        duration: TimeInterval
    ) async {
        var copy = task
        copy.title = title
        copy.notes = notes
        copy.estimatedDuration = duration
        do {
            try await services.taskRepository?.update(copy)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveUpcoming(from source: IndexSet, to destination: Int) {
        var ordered = upcoming
        ordered.move(fromOffsets: source, toOffset: destination)
        var full = activeTasks
        if let head = headTask {
            full = [head] + ordered
        } else {
            full = ordered
        }
        Task {
            do {
                try await services.taskRepository?.reorder(orderedIDs: full.map(\.id))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func undoCompletion() async {
        do {
            _ = try await services.taskRepository?.undoLastCompletion()
            undoTaskTitle = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ActiveTaskHero: View {
    let task: QueueTask
    var onEdit: () -> Void
    var onFocus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: QueueSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: QueueSpacing.xs) {
                    Text(task.title)
                        .font(QueueTypography.title(30))
                        .foregroundStyle(QueueColors.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    Text(durationLabel(task.estimatedDuration))
                        .font(QueueTypography.body())
                        .foregroundStyle(QueueColors.secondaryText)
                }
                Spacer()
                CompanionAnimationView(state: .idle, reduceMotion: false)
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
            }

            if let notes = task.notes, !notes.isEmpty {
                Text(notes)
                    .font(QueueTypography.body(15))
                    .foregroundStyle(QueueColors.secondaryText)
            }

            Button("Start focus", action: onFocus)
                .buttonStyle(QueuePrimaryButtonStyle())
                .accessibilityHint("Opens the immersive focus experience")

            Button("Edit task", action: onEdit)
                .font(QueueTypography.caption())
                .foregroundStyle(QueueColors.sageDeep)
                .accessibilityHint("Opens the editor for the active task")
        }
        .padding(QueueSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: QueueSpacing.cornerSoft, style: .continuous)
                .fill(QueueColors.secondarySurface)
        )
    }

    private func durationLabel(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(interval / 60))
        return "\(minutes) min estimate"
    }
}

private struct UpcomingTaskRow: View {
    let task: QueueTask

    var body: some View {
        HStack(spacing: QueueSpacing.md) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(QueueColors.secondaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(QueueTypography.headline(17))
                    .foregroundStyle(QueueColors.primaryText)
                Text("\(max(1, Int(task.estimatedDuration / 60))) min")
                    .font(QueueTypography.caption())
                    .foregroundStyle(QueueColors.secondaryText)
            }
            Spacer()
        }
        .padding(.vertical, QueueSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title), \(max(1, Int(task.estimatedDuration / 60))) minutes")
        .accessibilityHint("Drag to reorder")
    }
}
