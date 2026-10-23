import UIKit
import XCTest
import SwiftData
import QueueCore
@testable import Queue

/// Settings writes the existing `UserPreferencesEntity` fields, including auto-start.
@MainActor
final class SettingsPreferencePersistenceTests: XCTestCase {
    func testSettingsEditsRoundTripWithoutTouchingAutoStart() throws {
        let container = try AppModelContainer.makeInMemory()
        let context = ModelContext(container)
        let prefs = UserPreferencesEntity(
            hasCompletedOnboarding: true,
            motivationProfile: .balanced,
            companionVisible: true,
            animationIntensity: "future-value",
            autoStartNextTask: true,
            dailyGoalCount: 3,
            showPlannedStartTimes: false
        )
        context.insert(prefs)

        XCTAssertEqual(AnimationIntensity.resolved(prefs.animationIntensityRaw), .standard)
        XCTAssertEqual(prefs.animationIntensityRaw, "future-value")

        UserPreferencesSettingsEditor.setCompanionVisible(false, on: prefs)
        UserPreferencesSettingsEditor.setAnimationIntensity(.reduced, on: prefs)
        UserPreferencesSettingsEditor.setMotivationProfile(.consistencyBuilder, on: prefs)
        UserPreferencesSettingsEditor.setDailyGoalCount(99, on: prefs)
        UserPreferencesSettingsEditor.setShowPlannedStartTimes(true, on: prefs)
        try context.save()

        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<UserPreferencesEntity>()).first)
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserPreferencesEntity>()).count, 1)
        XCTAssertTrue(stored.autoStartNextTask)
        XCTAssertTrue(stored.hasCompletedOnboarding)
        XCTAssertFalse(stored.companionVisible)
        XCTAssertEqual(stored.animationIntensityRaw, AnimationIntensity.reduced.rawValue)
        XCTAssertEqual(stored.motivationProfile, .consistencyBuilder)
        XCTAssertEqual(stored.dailyGoalCount, DailyGoalCount.maximum)
        XCTAssertTrue(stored.showPlannedStartTimes)
    }

    func testAutoStartToggleWritesTheExistingColumn() throws {
        let container = try AppModelContainer.makeInMemory()
        let context = ModelContext(container)
        let prefs = UserPreferencesEntity(autoStartNextTask: false)
        context.insert(prefs)

        UserPreferencesSettingsEditor.setAutoStartNextTask(true, on: prefs)
        try context.save()
        var stored = try XCTUnwrap(context.fetch(FetchDescriptor<UserPreferencesEntity>()).first)
        XCTAssertTrue(stored.autoStartNextTask)
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserPreferencesEntity>()).count, 1)

        UserPreferencesSettingsEditor.setAutoStartNextTask(false, on: prefs)
        try context.save()
        stored = try XCTUnwrap(context.fetch(FetchDescriptor<UserPreferencesEntity>()).first)
        XCTAssertFalse(stored.autoStartNextTask)
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserPreferencesEntity>()).count, 1)
    }

    func testVersionRowReadsTheAppBundle() throws {
        let bundle = try XCTUnwrap(Bundle(identifier: "com.queueapp.Queueup"))
        let short = try XCTUnwrap(
            bundle.object(forInfoDictionaryKey: AppVersionFormatting.shortVersionInfoKey) as? String
        )
        let build = try XCTUnwrap(
            bundle.object(forInfoDictionaryKey: AppVersionFormatting.buildInfoKey) as? String
        )
        XCTAssertFalse(short.isEmpty)
        XCTAssertFalse(build.isEmpty)
        let displayed = AppVersionFormatting.display(in: bundle)
        XCTAssertEqual(displayed, "\(short) (\(build))")
        XCTAssertNotEqual(displayed, "0.1.0-phase1")
    }

    func testNotificationsRowUsesTheSystemSettingsURL() {
        let url = AppSettingsLink.url
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, UIApplication.openSettingsURLString)
    }
}
