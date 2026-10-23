import SwiftData
import Foundation
import QueueCore

enum AppModelContainer {
    /// `migrateLegacyStore` is true for the app, which can still see the pre-App-Group file.
    /// The widget passes false so it never creates an empty store ahead of that copy.
    static func make(migrateLegacyStore: Bool = true) -> ModelContainer {
        let schema = Schema([
            TaskEntity.self,
            FocusSessionEntity.self,
            XPTransactionEntity.self,
            UserPreferencesEntity.self
        ])
        let configuration: ModelConfiguration
        if let url = AppGroupStoreLocation.prepareStoreURL(migrateLegacy: migrateLegacyStore) {
            configuration = ModelConfiguration(
                "QueueLocalStore",
                schema: schema,
                url: url,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                "QueueLocalStore",
                schema: schema,
                isStoredInMemoryOnly: false
            )
        }
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Recoverable fallback for corrupted local store during development.
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [memory])
        }
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
