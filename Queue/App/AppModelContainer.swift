import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: "com.queueapp.Queueup", category: "persistence")

/// Opens the on-disk SwiftData store used by the app.
///
/// The store file is `QueueLocalStore` in the app sandbox (Application Support),
/// which is where TestFlight builds already write. Widgets and Live Activities
/// do not open this store; they read `FocusActivityStore` in the App Group
/// `group.com.queueapp.Queueup`. Do not retarget this container at that group,
/// or existing installs will look at an empty directory and leave the real
/// store behind.
enum AppModelContainer {
    /// Configuration name. Also the on-disk store name for the default location.
    static let storeName = "QueueLocalStore"

    static let schema = Schema(versionedSchema: QueueSchemaV1.self)

    enum OpenResult {
        case ready(ModelContainer)
        case failed(Error)
    }

    /// Production launch. A failure is returned to the caller.
    ///
    /// This never substitutes an in-memory store. An in-memory store would look
    /// like a normal launch with no tasks, and the real file would sit unused.
    /// It also never deletes or replaces the store file.
    static func open(storeURL: URL? = nil) -> OpenResult {
        do {
            return .ready(try makePersistent(storeURL: storeURL))
        } catch {
            let description = String(describing: error)
            logger.error("Failed to open \(storeName, privacy: .public): \(description, privacy: .public)")
            return .failed(error)
        }
    }

    /// On-disk container. `storeURL` overrides the location for tests; production
    /// passes nil and keeps the historical `QueueLocalStore` configuration.
    static func makePersistent(storeURL: URL? = nil) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: QueueMigrationPlan.self,
            configurations: [persistentConfiguration(storeURL: storeURL)]
        )
    }

    /// Explicit in-memory store for previews and tests. Not used at launch.
    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "QueuePreviewStore",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: QueueMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// Disk configuration. Passing nil uses the same name and sandbox location
    /// as builds that shipped before the migration plan existed.
    static func persistentConfiguration(storeURL: URL? = nil) -> ModelConfiguration {
        if let storeURL {
            return ModelConfiguration(storeName, schema: schema, url: storeURL)
        }
        return ModelConfiguration(
            storeName,
            schema: schema,
            isStoredInMemoryOnly: false
        )
    }
}
