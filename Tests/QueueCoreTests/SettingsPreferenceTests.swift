import Foundation
import Testing
@testable import QueueCore

@Suite("Settings preferences")
struct SettingsPreferenceTests {
    @Test("Animation intensity raw values match the strings already stored")
    func animationIntensityRawValues() {
        #expect(AnimationIntensity.reduced.rawValue == "reduced")
        #expect(AnimationIntensity.standard.rawValue == "standard")
        #expect(AnimationIntensity.resolved("reduced") == .reduced)
        #expect(AnimationIntensity.resolved("standard") == .standard)
        #expect(AnimationIntensity.resolved("future-value") == .standard)
        #expect(AnimationIntensity.resolved("").allowsMotion)
        #expect(AnimationIntensity.reduced.allowsMotion == false)
        #expect(AnimationIntensity.standard.allowsMotion)
        #expect(AnimationIntensity.allCases.allSatisfy { !$0.summary.isEmpty && !$0.displayName.isEmpty })
    }

    @Test("Motivation profiles keep the onboarding names")
    func motivationNames() {
        #expect(MotivationProfile.balanced.displayName == "Balanced")
        #expect(MotivationProfile.speedRunner.displayName == "Speed Runner")
        #expect(MotivationProfile.consistencyBuilder.displayName == "Consistency Builder")
        #expect(MotivationProfile.balanced.summary == "Completion plus modest on-time bonuses.")
        #expect(MotivationProfile.speedRunner.summary == "More emphasis on finishing within estimates.")
        #expect(MotivationProfile.consistencyBuilder.summary == "Streaks and daily rhythm over speed.")
        let names = MotivationProfile.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
    }

    @Test("Companion visibility defaults on until the app publishes a choice")
    func companionVisibilityStore() {
        let suite = "queue.companion.preference.tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(CompanionPreferenceStore.isVisible(defaults: defaults))
        CompanionPreferenceStore.setVisible(false, defaults: defaults)
        #expect(CompanionPreferenceStore.isVisible(defaults: defaults) == false)
        CompanionPreferenceStore.setVisible(true, defaults: defaults)
        #expect(CompanionPreferenceStore.isVisible(defaults: defaults))
    }

    @Test("Daily goal count clamps into the stepper range")
    func dailyGoalClamp() {
        #expect(DailyGoalCount.clamped(3) == 3)
        #expect(DailyGoalCount.clamped(0) == 1)
        #expect(DailyGoalCount.clamped(99) == 10)
        #expect(DailyGoalCount.range == 1...10)
        #expect(DailyGoalCount.label(for: 1) == "1 task")
        #expect(DailyGoalCount.label(for: 3) == "3 tasks")
    }

    @Test("Version text joins the short version and the build number")
    func versionText() {
        #expect(AppVersionFormatting.shortVersionInfoKey == "CFBundleShortVersionString")
        #expect(AppVersionFormatting.buildInfoKey == "CFBundleVersion")
        #expect(AppVersionFormatting.display(shortVersion: "0.1.2", build: "3") == "0.1.2 (3)")
        #expect(AppVersionFormatting.display(shortVersion: " 0.1.2 ", build: " 3 ") == "0.1.2 (3)")
        #expect(AppVersionFormatting.display(shortVersion: "0.1.2", build: nil) == "0.1.2")
        #expect(AppVersionFormatting.display(shortVersion: "0.1.2", build: "   ") == "0.1.2")
        #expect(AppVersionFormatting.display(shortVersion: nil, build: "3") == "3")
        #expect(AppVersionFormatting.display(shortVersion: nil, build: nil) == "Unknown")
        #expect(AppVersionFormatting.display(shortVersion: "", build: "") == "Unknown")
    }

    @Test("Bundle version display reads those two info keys")
    func bundleVersionReadsInfoKeys() {
        let bundle = Bundle(for: SettingsBundleProbe.self)
        let short = bundle.object(forInfoDictionaryKey: AppVersionFormatting.shortVersionInfoKey) as? String
        let build = bundle.object(forInfoDictionaryKey: AppVersionFormatting.buildInfoKey) as? String
        #expect(AppVersionFormatting.display(in: bundle) == AppVersionFormatting.display(shortVersion: short, build: build))
    }

    @Test("Notification status is allowed only when alerts can be scheduled")
    func notificationStatus() {
        #expect(NotificationSettingsStatus.label(for: .authorized) == "Allowed")
        #expect(NotificationSettingsStatus.label(for: .denied) == "Not allowed")
        #expect(NotificationSettingsStatus.label(for: .notDetermined) == "Not allowed")
        #expect(NotificationSettingsStatus.isAllowed(.authorized))
        #expect(NotificationSettingsStatus.isAllowed(.denied) == false)
        #expect(NotificationSettingsStatus.isAllowed(.notDetermined) == false)
    }

    @Test("The legacy start-time flag is copied once the preferences row exists")
    func adoptLegacyStartTimes() {
        let waitingForRow = PlannedStartTimePreference.adopt(
            entityValue: false,
            legacyValue: true,
            entityExists: false
        )
        #expect(waitingForRow == PlannedStartTimeAdoption(entityValue: false, clearLegacy: false))

        let adopted = PlannedStartTimePreference.adopt(
            entityValue: false,
            legacyValue: true,
            entityExists: true
        )
        #expect(adopted == PlannedStartTimeAdoption(entityValue: true, clearLegacy: true))

        let alreadyOn = PlannedStartTimePreference.adopt(
            entityValue: true,
            legacyValue: true,
            entityExists: true
        )
        #expect(alreadyOn == PlannedStartTimeAdoption(entityValue: true, clearLegacy: true))

        let untouched = PlannedStartTimePreference.adopt(
            entityValue: false,
            legacyValue: false,
            entityExists: true
        )
        #expect(untouched == PlannedStartTimeAdoption(entityValue: false, clearLegacy: false))

        let explicitOn = PlannedStartTimePreference.adopt(
            entityValue: true,
            legacyValue: false,
            entityExists: true
        )
        #expect(explicitOn == PlannedStartTimeAdoption(entityValue: true, clearLegacy: false))
    }
}

private final class SettingsBundleProbe {}
