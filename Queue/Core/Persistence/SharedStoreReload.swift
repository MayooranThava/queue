import Foundation
import SwiftData
import QueueCore

struct SharedStoreDump {
    var tasks: [QueueTask]
    var session: FocusSession?
    var transactions: [XPTransaction]

    @MainActor
    static func load() throws -> SharedStoreDump {
        let container = AppModelContainer.make(migrateLegacyStore: false)
        let context = ModelContext(container)
        let tasks = try context.fetch(FetchDescriptor<TaskEntity>()).map { $0.asDomain() }
        let sessions = FetchDescriptor<FocusSessionEntity>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let session = try context.fetch(sessions).first?.asDomain()
        let transactions = try context.fetch(FetchDescriptor<XPTransactionEntity>()).compactMap { $0.asDomain() }
        return SharedStoreDump(tasks: tasks, session: session, transactions: transactions)
    }
}
