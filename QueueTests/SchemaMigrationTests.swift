import XCTest
import SwiftData
import QueueCore
@testable import Queue

/// SwiftData schema tests run in the app-hosted QueueTests target.
/// QueueCore stays free of SwiftData so `swift test` can run the domain package
/// without these iOS models. The models here are the same top-level `@Model`
/// types TestFlight already stored; moving them would change that identity.
final class SchemaMigrationTests: XCTestCase {
    func testV1UsesShippingModelTypesAndVersion() {
        XCTAssertEqual(QueueSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(
            QueueSchemaV1.models.map { ObjectIdentifier($0) },
            [
                ObjectIdentifier(TaskEntity.self),
                ObjectIdentifier(FocusSessionEntity.self),
                ObjectIdentifier(XPTransactionEntity.self),
                ObjectIdentifier(UserPreferencesEntity.self),
            ]
        )
    }

    func testMigrationPlanIsV1Only() {
        XCTAssertEqual(
            QueueMigrationPlan.schemas.map { ObjectIdentifier($0) },
            [ObjectIdentifier(QueueSchemaV1.self)]
        )
        XCTAssertTrue(QueueMigrationPlan.stages.isEmpty)
    }

    func testVersionedStoreRoundTripsSampleData() throws {
        let directory = try makeStoreDirectory()
        defer { removeStoreDirectory(directory) }
        let url = storeURL(in: directory)
        let sample = SampleStore.make()

        try autoreleasepool {
            let container = try AppModelContainer.makePersistent(storeURL: url)
            try write(sample, to: container)
        }
        try autoreleasepool {
            let container = try AppModelContainer.makePersistent(storeURL: url)
            try assertStore(sample, in: container)
            XCTAssertFalse(container.configurations.contains { $0.isStoredInMemoryOnly })
        }
    }

    /// Writes a store the way TestFlight did (same models, same store name, no
    /// migration plan), then opens it with `QueueMigrationPlan`.
    func testLegacyUnversionedStoreRoundTripsThroughMigrationPlan() throws {
        let directory = try makeStoreDirectory()
        defer { removeStoreDirectory(directory) }
        let url = storeURL(in: directory)
        let sample = SampleStore.make()

        try autoreleasepool {
            let container = try makeLegacyUnversionedContainer(at: url)
            try write(sample, to: container)
        }
        try autoreleasepool {
            let container = try AppModelContainer.makePersistent(storeURL: url)
            try assertStore(sample, in: container)
        }
    }

    func testOpenUsesDiskStore() throws {
        let directory = try makeStoreDirectory()
        defer { removeStoreDirectory(directory) }
        let url = storeURL(in: directory)

        let result = AppModelContainer.open(storeURL: url)
        guard case .ready(let container) = result else {
            XCTFail("Expected a disk store, got \(String(describing: result))")
            return
        }
        XCTAssertFalse(container.configurations.isEmpty)
        XCTAssertTrue(container.configurations.allSatisfy { !$0.isStoredInMemoryOnly })
        XCTAssertEqual(container.configurations.first?.name, AppModelContainer.storeName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let widgetContainer = try AppModelContainer.makePersistent(migrateLegacyStore: false, storeURL: url)
        XCTAssertTrue(widgetContainer.configurations.allSatisfy { !$0.isStoredInMemoryOnly })
    }

    func testInMemoryStoreIsExplicit() throws {
        let container = try AppModelContainer.makeInMemory()
        XCTAssertFalse(container.configurations.isEmpty)
        XCTAssertTrue(container.configurations.allSatisfy(\.isStoredInMemoryOnly))
        XCTAssertFalse(container.configurations.contains { $0.name == AppModelContainer.storeName })
    }

    func testProductionConfigurationStaysOnDisk() {
        for migrateLegacyStore in [true, false] {
            let configuration = AppModelContainer.persistentConfiguration(migrateLegacyStore: migrateLegacyStore)
            XCTAssertEqual(configuration.name, "QueueLocalStore")
            XCTAssertFalse(configuration.isStoredInMemoryOnly)
            let path = configuration.url.path
            XCTAssertTrue(
                path.contains("QueueLocalStore") || path.contains("default.store"),
                "Unexpected store URL: \(path)"
            )
        }
    }

    func testOpenFailureDoesNotSubstituteInMemoryStore() throws {
        let directory = try makeStoreDirectory()
        let url = storeURL(in: directory)
        let original = Data("precious-user-data".utf8)
        try original.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { removeStoreDirectory(directory) }

        XCTAssertThrowsError(try AppModelContainer.makePersistent(storeURL: url))
        XCTAssertThrowsError(try AppModelContainer.makePersistent(migrateLegacyStore: false, storeURL: url))
        let result = AppModelContainer.open(storeURL: url)
        guard case .failed = result else {
            XCTFail("Persistent open failure returned a container: \(String(describing: result))")
            return
        }

        XCTAssertEqual(try Data(contentsOf: url), original)
        let names = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .sorted()
        XCTAssertEqual(names, [url.lastPathComponent])
    }

    // MARK: - Legacy store

    /// The container initializer TestFlight used: an unversioned schema, the
    /// `QueueLocalStore` name, and no migration plan.
    private func makeLegacyUnversionedContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema([
            TaskEntity.self,
            FocusSessionEntity.self,
            XPTransactionEntity.self,
            UserPreferencesEntity.self,
        ])
        let configuration = ModelConfiguration(
            "QueueLocalStore",
            schema: schema,
            url: url
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: - Sample rows

    private struct SampleStore {
        var task: QueueTask
        var session: FocusSession
        var transaction: XPTransaction
        var hasCompletedOnboarding: Bool
        var motivationProfile: MotivationProfile
        var companionVisible: Bool
        var animationIntensity: String
        var autoStartNextTask: Bool
        var dailyGoalCount: Int
        var showPlannedStartTimes: Bool

        static func make() -> SampleStore {
            let taskID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
            let extensionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
            let sessionID = UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!
            let transactionID = UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!
            let sourceEventID = UUID(uuidString: "12345678-9ABC-DEF0-1234-56789ABCDEF0")!
            let created = Date(timeIntervalSinceReferenceDate: 700_000_000)
            let task = QueueTestFixture.makeTask(
                id: taskID,
                title: "Write the migration",
                notes: "Keep the TestFlight store",
                estimatedDuration: 25 * 60,
                difficulty: .hard,
                plannedStartAt: created.addingTimeInterval(100),
                createdAt: created,
                scheduledDate: created.addingTimeInterval(3_600),
                queuePosition: 2,
                status: .paused,
                startedAt: created.addingTimeInterval(200),
                completedAt: nil,
                actualFocusDuration: 120,
                accumulatedPausedDuration: 30,
                extensions: [
                    TimerExtension(id: extensionID, duration: 300, createdAt: created.addingTimeInterval(300))
                ],
                category: "Deep work",
                calendarEventID: "event-42",
                xpAwardID: transactionID,
                modifiedAt: created.addingTimeInterval(400)
            )
            let session = FocusSession(
                id: sessionID,
                taskID: taskID,
                sessionStart: created.addingTimeInterval(200),
                segmentStart: created.addingTimeInterval(500),
                plannedDuration: 25 * 60,
                accumulatedActive: 120,
                accumulatedPaused: 30,
                state: .paused,
                extensions: [
                    FocusTimerExtension(id: extensionID, duration: 300, createdAt: created.addingTimeInterval(300))
                ],
                completedAt: nil
            )
            let transaction = XPTransaction(
                id: transactionID,
                sourceEventID: sourceEventID,
                taskID: taskID,
                rewardType: .taskCompleted,
                amount: 42,
                timestamp: created.addingTimeInterval(600)
            )
            return SampleStore(
                task: task,
                session: session,
                transaction: transaction,
                hasCompletedOnboarding: true,
                motivationProfile: .speedRunner,
                companionVisible: false,
                animationIntensity: "reduced",
                autoStartNextTask: true,
                dailyGoalCount: 5,
                showPlannedStartTimes: true
            )
        }
    }

    private func write(_ sample: SampleStore, to container: ModelContainer) throws {
        let context = ModelContext(container)
        context.insert(TaskEntity(from: sample.task))
        context.insert(FocusSessionEntity(session: sample.session))
        context.insert(XPTransactionEntity(from: sample.transaction))
        context.insert(UserPreferencesEntity(
            hasCompletedOnboarding: sample.hasCompletedOnboarding,
            motivationProfile: sample.motivationProfile,
            companionVisible: sample.companionVisible,
            animationIntensity: sample.animationIntensity,
            autoStartNextTask: sample.autoStartNextTask,
            dailyGoalCount: sample.dailyGoalCount,
            showPlannedStartTimes: sample.showPlannedStartTimes
        ))
        try context.save()
    }

    private func assertStore(
        _ sample: SampleStore,
        in container: ModelContainer,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        let context = ModelContext(container)
        let tasks = try context.fetch(FetchDescriptor<TaskEntity>())
        XCTAssertEqual(tasks.map { $0.asDomain() }, [sample.task], file: file, line: line)

        let sessions = try context.fetch(FetchDescriptor<FocusSessionEntity>())
        XCTAssertEqual(sessions.count, 1, file: file, line: line)
        XCTAssertEqual(sessions.first?.asDomain(), sample.session, file: file, line: line)

        let transactions = try context.fetch(FetchDescriptor<XPTransactionEntity>())
        XCTAssertEqual(transactions.compactMap { $0.asDomain() }, [sample.transaction], file: file, line: line)

        let preferences = try context.fetch(FetchDescriptor<UserPreferencesEntity>())
        let prefs = try XCTUnwrap(preferences.first, file: file, line: line)
        XCTAssertEqual(preferences.count, 1, file: file, line: line)
        XCTAssertEqual(prefs.hasCompletedOnboarding, sample.hasCompletedOnboarding, file: file, line: line)
        XCTAssertEqual(prefs.motivationProfile, sample.motivationProfile, file: file, line: line)
        XCTAssertEqual(prefs.companionVisible, sample.companionVisible, file: file, line: line)
        XCTAssertEqual(prefs.animationIntensityRaw, sample.animationIntensity, file: file, line: line)
        XCTAssertEqual(prefs.autoStartNextTask, sample.autoStartNextTask, file: file, line: line)
        XCTAssertEqual(prefs.dailyGoalCount, sample.dailyGoalCount, file: file, line: line)
        XCTAssertEqual(prefs.showPlannedStartTimes, sample.showPlannedStartTimes, file: file, line: line)
    }

    // MARK: - Files

    private func makeStoreDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("queue-schema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func storeURL(in directory: URL) -> URL {
        directory.appendingPathComponent("QueueLocalStore.store")
    }

    private func removeStoreDirectory(_ directory: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        if let names = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for url in names {
                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            }
        }
        try? FileManager.default.removeItem(at: directory)
    }
}
