import Foundation
import os
import QueueCore
import SwiftData

private let logger = Logger(subsystem: "com.queueapp.Queueup", category: "persistence")

/// Opens the on-disk SwiftData store shared by the app, widgets, and App Intents.
///
/// The live file is `QueueLocalStore.store` in the App Group
/// `group.com.queueapp.Queueup`. The first app launch copies the pre-App-Group
/// sandbox file (TestFlight) into that location and leaves the original in place.
/// If the App Group is unavailable, the opener falls back to that sandbox file.
///
/// Every persistent container uses `QueueSchemaV1` and `QueueMigrationPlan`.
/// Nothing here substitutes an in-memory store. `makeInMemory()` is only for
/// previews and tests.
enum AppModelContainer {
    /// Configuration name. Also the on-disk store name for the sandbox fallback.
    static let storeName = "QueueLocalStore"

    static let schema = Schema(versionedSchema: QueueSchemaV1.self)

    enum OpenResult {
        case ready(ModelContainer)
        case failed(Error)
    }

    /// App launch. Copies the legacy sandbox store into the App Group once.
    ///
    /// A failure is returned to the caller. This never substitutes an in-memory
    /// store and never deletes the caller's store file.
    static func open(storeURL: URL? = nil) -> OpenResult {
        do {
            return .ready(try makePersistent(migrateLegacyStore: storeURL == nil, storeURL: storeURL))
        } catch {
            let description = String(describing: error)
            logger.error("Failed to open \(storeName, privacy: .public): \(description, privacy: .public)")
            return .failed(error)
        }
    }

    /// On-disk container.
    ///
    /// `storeURL` overrides the location for tests. The app passes nil so the
    /// shared App Group file is used. Widgets and App Intents pass
    /// `migrateLegacyStore: false` so they never create that file ahead of the
    /// app's copy.
    static func makePersistent(migrateLegacyStore: Bool = true, storeURL: URL? = nil) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: QueueMigrationPlan.self,
            configurations: [persistentConfiguration(migrateLegacyStore: migrateLegacyStore, storeURL: storeURL)]
        )
    }

    /// Explicit in-memory store for previews and tests. Not used at launch,
    /// and not used by widgets or App Intents.
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

    /// Disk configuration. An explicit `storeURL` wins. Otherwise this is the
    /// App Group file, or the historical sandbox store when that container is missing.
    static func persistentConfiguration(migrateLegacyStore: Bool = true, storeURL: URL? = nil) -> ModelConfiguration {
        if let storeURL {
            return ModelConfiguration(
                storeName,
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
        }
        if let url = AppGroupStoreLocation.prepareStoreURL(migrateLegacy: migrateLegacyStore) {
            return ModelConfiguration(
                storeName,
                schema: schema,
                url: url,
                cloudKitDatabase: .none
            )
        }
        return ModelConfiguration(
            storeName,
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
    }
}

enum AppGroupStoreLocation {
    static let storeFileName = "QueueLocalStore.store"
    static let migrationMarker = "queue.store.migrated.v1"

    static func widgetMayOpenStore() -> Bool {
        AppGroupStoreMigration.widgetMayOpenStore(
            appGroupAvailable: containerURL() != nil,
            markerExists: markerExists()
        )
    }

    static func prepareStoreURL(migrateLegacy: Bool) -> URL? {
        let fileManager = FileManager.default
        guard let container = containerURL() else { return nil }
        let directory = container.appendingPathComponent("Library/Application Support", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            let description = String(describing: error)
            logger.error("Failed to create the App Group store directory: \(description, privacy: .public)")
            return nil
        }

        let destination = directory.appendingPathComponent(storeFileName)
        let marker = directory.appendingPathComponent(migrationMarker)
        if migrateLegacy && !fileManager.fileExists(atPath: marker.path) {
            let legacy = legacyStoreURL()
            let legacyExists = legacy.map { fileManager.fileExists(atPath: $0.path) } ?? false
            if AppGroupStoreMigration.shouldCopyLegacyStore(
                legacyExists: legacyExists,
                destinationExists: fileManager.fileExists(atPath: destination.path),
                markerExists: false
            ), let legacy {
                do {
                    try copyStore(from: legacy, to: destination)
                } catch {
                    // Leave the marker unset and keep the sandbox store so the next launch can retry.
                    let description = String(describing: error)
                    logger.error("Failed to copy the legacy store into the App Group: \(description, privacy: .public)")
                    return nil
                }
            }
            fileManager.createFile(atPath: marker.path, contents: Data("1".utf8))
        }
        return destination
    }

    private static func containerURL() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: FocusActivityStore.appGroupID
        )
    }

    private static func markerExists() -> Bool {
        guard let container = containerURL() else { return false }
        let marker = container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(migrationMarker)
        return FileManager.default.fileExists(atPath: marker.path)
    }

    private static func legacyStoreURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return findStore(in: appSupport, depth: 3)
    }

    /// SwiftData has used both `QueueLocalStore.store` and `default.store` depending on OS version.
    private static func findStore(in directory: URL, depth: Int) -> URL? {
        let fileManager = FileManager.default
        let preferred = ["QueueLocalStore.store", "default.store"]
        for name in preferred {
            let url = directory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        guard depth > 0,
              let children = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              )
        else { return nil }
        for child in children {
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory, let nested = findStore(in: child, depth: depth - 1) else { continue }
            return nested
        }
        return nil
    }

    private static func copyStore(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        for suffix in ["-shm", "-wal"] {
            let from = URL(fileURLWithPath: source.path + suffix)
            let to = URL(fileURLWithPath: destination.path + suffix)
            guard fileManager.fileExists(atPath: from.path) else { continue }
            if fileManager.fileExists(atPath: to.path) {
                try fileManager.removeItem(at: to)
            }
            try fileManager.copyItem(at: from, to: to)
        }
    }
}
