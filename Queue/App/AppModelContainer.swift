import SwiftData
import Foundation

enum AppModelContainer {
    static func make() -> ModelContainer {
        let schema = Schema([
            TaskEntity.self,
            XPTransactionEntity.self,
            UserPreferencesEntity.self
        ])
        let configuration = ModelConfiguration(
            "QueueLocalStore",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Recoverable fallback for corrupted local store during development.
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [memory])
        }
    }
}
