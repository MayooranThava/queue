import SwiftUI
import SwiftData
import QueueCore

@MainActor
final class AppServices: ObservableObject {
    let queueService: TaskQueueService
    let analytics: AnalyticsClient
    private(set) var taskRepository: TaskRepository?
    private var didBootstrap = false

    init(
        queueService: TaskQueueService = TaskQueueService(),
        analytics: AnalyticsClient = InMemoryAnalyticsClient()
    ) {
        self.queueService = queueService
        self.analytics = analytics
    }

    func configure(modelContext: ModelContext) async {
        if taskRepository == nil {
            taskRepository = TaskRepository(
                context: modelContext,
                queueService: queueService,
                analytics: analytics
            )
        }
        guard !didBootstrap else { return }
        do {
            try await taskRepository?.bootstrapFromStore()
            didBootstrap = true
        } catch {
            // Store may be empty on first launch.
            didBootstrap = true
        }
    }
}
