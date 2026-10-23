import Foundation
import Testing
@testable import QueueCore

@Suite("Queue themes")
struct QueueThemeTests {
    @Test("Six themes keep their ids, names, and Pro flags")
    func catalog() {
        #expect(QueueTheme.all.map(\.id) == ["forest", "harbor", "lagoon", "mocha", "dusk", "cloud"])
        #expect(QueueTheme.all.map(\.name) == ["Forest", "Harbor", "Lagoon", "Mocha", "Dusk", "Cloud"])
        #expect(QueueTheme.forest.isPro == false)
        #expect(QueueTheme.harbor.isPro == false)
        #expect(QueueTheme.cloud.isPro == false)
        #expect(QueueTheme.lagoon.isPro)
        #expect(QueueTheme.mocha.isPro)
        #expect(QueueTheme.dusk.isPro)
        #expect(QueueTheme.theme(id: nil).id == "forest")
        #expect(QueueTheme.theme(id: "nope").id == "forest")
        #expect(Set(QueueTheme.all.map(\.id)).count == QueueTheme.all.count)
    }

    @Test("Forest uses the approved colour-vision success and danger")
    func forestColourVision() {
        #expect(QueueTheme.forest.light.success.hex == "34794B")
        #expect(QueueTheme.forest.dark.success.hex == "A3E0AB")
        #expect(QueueTheme.forest.light.danger.hex == "8F2A1E")
        #expect(QueueTheme.forest.dark.danger.hex == "EB8370")
        #expect(QueueTheme.forest.light.success.hex != "3D6B37")
        #expect(QueueTheme.forest.dark.success.hex != "8FC27E")
        #expect(QueueTheme.forest.light.danger.hex != "A23B2E")
        #expect(QueueTheme.forest.dark.danger.hex != "EC8A74")
        #expect(QueueTheme.cloud.light.background.hex == "F0EEE9")
        #expect(QueueTheme.cloud.dark.background.hex == "000000")
    }

    @Test("Stored hex values match the theme spec")
    func hexValues() {
        let expected: [String: (light: [QueuePaletteRole: String], dark: [QueuePaletteRole: String])] = [
            "forest": (
                light: [
                    .background: "FAF7F0", .surface: "EEF2EA", .textPrimary: "1F2A1B", .textSecondary: "566150",
                    .primary: "A9532A", .onPrimary: "FAF7F0", .accent: "E9A84E", .onAccent: "1F2A1B",
                    .success: "34794B", .danger: "8F2A1E"
                ],
                dark: [
                    .background: "1A2617", .surface: "263620", .textPrimary: "FAF7F0", .textSecondary: "B4C2AE",
                    .primary: "E0814F", .onPrimary: "1A2617", .accent: "F0B85A", .onAccent: "1A2617",
                    .success: "A3E0AB", .danger: "EB8370"
                ]
            ),
            "harbor": (
                light: [
                    .background: "F5F7FA", .surface: "E6ECF3", .textPrimary: "16202C", .textSecondary: "4E5B6A",
                    .primary: "2F5D8A", .onPrimary: "FFFFFF", .accent: "E9A84E", .onAccent: "16202C",
                    .success: "2E6B55", .danger: "9C3321"
                ],
                dark: [
                    .background: "121A24", .surface: "1C2733", .textPrimary: "F2F5F8", .textSecondary: "A9B6C4",
                    .primary: "86AEDA", .onPrimary: "121A24", .accent: "F0B85A", .onAccent: "121A24",
                    .success: "7EC8A9", .danger: "E07D6C"
                ]
            ),
            "lagoon": (
                light: [
                    .background: "F4F8F7", .surface: "E3EEEB", .textPrimary: "142624", .textSecondary: "4A5F5B",
                    .primary: "1F6F6B", .onPrimary: "FFFFFF", .accent: "E7A64C", .onAccent: "142624",
                    .success: "2F6F41", .danger: "8A1A14"
                ],
                dark: [
                    .background: "0F2221", .surface: "183230", .textPrimary: "F1F7F5", .textSecondary: "A6BFBA",
                    .primary: "62C0B6", .onPrimary: "0F2221", .accent: "F0B85A", .onAccent: "0F2221",
                    .success: "A7E2AC", .danger: "EB8370"
                ]
            ),
            "mocha": (
                light: [
                    .background: "FAF5F0", .surface: "F1E7DE", .textPrimary: "2B1F18", .textSecondary: "66554A",
                    .primary: "865A44", .onPrimary: "FAF5F0", .accent: "EDB45A", .onAccent: "2B1F18",
                    .success: "2F6F57", .danger: "972C20"
                ],
                dark: [
                    .background: "1F1712", .surface: "2C211A", .textPrimary: "F7EFE8", .textSecondary: "C2B1A4",
                    .primary: "F0A884", .onPrimary: "1F1712", .accent: "F2C063", .onAccent: "1F1712",
                    .success: "97D3B1", .danger: "EB8675"
                ]
            ),
            "dusk": (
                light: [
                    .background: "F7F5FA", .surface: "ECE7F3", .textPrimary: "1E1A2B", .textSecondary: "585266",
                    .primary: "5B4B8A", .onPrimary: "FFFFFF", .accent: "E9A84E", .onAccent: "1E1A2B",
                    .success: "2E6B55", .danger: "8F241E"
                ],
                dark: [
                    .background: "17142A", .surface: "231F38", .textPrimary: "F4F2FA", .textSecondary: "B5AECA",
                    .primary: "AB9EE2", .onPrimary: "17142A", .accent: "F0B85A", .onAccent: "17142A",
                    .success: "88D7BA", .danger: "ED8782"
                ]
            ),
            "cloud": (
                light: [
                    .background: "F0EEE9", .surface: "E3E0D9", .textPrimary: "1C1C1A", .textSecondary: "54524D",
                    .primary: "3D4A57", .onPrimary: "FFFFFF", .accent: "E6A64E", .onAccent: "1C1C1A",
                    .success: "2F6F54", .danger: "8F2F1E"
                ],
                dark: [
                    .background: "000000", .surface: "161616", .textPrimary: "F0EEE9", .textSecondary: "A8A59E",
                    .primary: "C9D3DD", .onPrimary: "000000", .accent: "F0B85A", .onAccent: "000000",
                    .success: "86CBA4", .danger: "E07D6C"
                ]
            )
        ]
        for theme in QueueTheme.all {
            let pair = expected[theme.id]
            #expect(pair != nil, "missing spec for \(theme.id)")
            for role in QueuePaletteRole.allCases {
                #expect(theme.light.color(for: role).hex == pair?.light[role] ?? "", "\(theme.id) light \(role)")
                #expect(theme.dark.color(for: role).hex == pair?.dark[role] ?? "", "\(theme.id) dark \(role)")
            }
        }
    }

    @Test("Text and button pairs meet WCAG 4.5:1 in every theme")
    func textAndButtonContrast() {
        #expect(abs(QueueRGB(hex: "FFFFFF").contrastRatio(against: QueueRGB(hex: "000000")) - 21) < 0.001)
        let published = QueueTheme.forest.light.textPrimary.contrastRatio(against: QueueTheme.forest.light.background)
        #expect(abs(published - 13.97) < 0.02)

        let textPairs: [(QueuePaletteRole, QueuePaletteRole)] = [
            (.textPrimary, .background),
            (.textPrimary, .surface),
            (.textSecondary, .background),
            (.textSecondary, .surface),
            (.onPrimary, .primary),
            (.onPrimary, .danger),
            (.onAccent, .accent),
            (.success, .background),
            (.success, .surface),
            (.danger, .background),
            (.danger, .surface)
        ]
        let componentPairs: [(QueuePaletteRole, QueuePaletteRole)] = [
            (.primary, .background),
            (.primary, .surface)
        ]
        for theme in QueueTheme.all {
            for dark in [false, true] {
                let palette = dark ? theme.dark : theme.light
                let mode = dark ? "dark" : "light"
                for (text, fill) in textPairs {
                    let ratio = palette.color(for: text).contrastRatio(against: palette.color(for: fill))
                    #expect(ratio >= 4.5, "\(theme.name) \(mode) \(text) on \(fill) is \(ratio)")
                }
                for (text, fill) in componentPairs {
                    let ratio = palette.color(for: text).contrastRatio(against: palette.color(for: fill))
                    #expect(ratio >= 3, "\(theme.name) \(mode) \(text) on \(fill) is \(ratio)")
                }
                if dark {
                    let onBackground = palette.accent.contrastRatio(against: palette.background)
                    let onSurface = palette.accent.contrastRatio(against: palette.surface)
                    #expect(onBackground >= 4.5, "\(theme.name) dark accent on background is \(onBackground)")
                    #expect(onSurface >= 4.5, "\(theme.name) dark accent on surface is \(onSurface)")
                } else {
                    // Honey stays a badge fill in light mode. It is not text, a ring, or a hairline.
                    let honey = palette.accent.contrastRatio(against: palette.background)
                    #expect(honey < 3, "\(theme.name) light accent on background is \(honey)")
                }
            }
        }
    }

    @Test("Increased contrast shifts secondary text toward primary outside Forest")
    func increasedContrastShift() {
        let harbor = QueueTheme.harbor.light
        let shifted = QueueTheme.harbor.resolved(.textSecondary, dark: false, increasedContrast: true)
        #expect(shifted != harbor.textSecondary)
        let base = harbor.textSecondary.contrastRatio(against: harbor.surface)
        let boosted = shifted.contrastRatio(against: harbor.surface)
        #expect(boosted + 0.001 >= base)
        #expect(QueueTheme.forest.resolved(.textSecondary, dark: false, increasedContrast: true).hex == "566150")
        #expect(QueueTheme.forest.resolved(.success, dark: false, increasedContrast: true).hex == "34794B")
    }

    @Test("The choice round-trips through defaults, including Pro themes")
    func storeRoundTrip() {
        let suite = "queue.theme.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(QueueThemeStore.current(defaults: defaults).id == QueueTheme.forest.id)
        QueueThemeStore.save(.harbor, defaults: defaults)
        #expect(QueueThemeStore.current(defaults: defaults).id == "harbor")
        #expect(QueueThemeStore.current(defaults: defaults).isPro == false)

        QueueThemeStore.save(.dusk, defaults: defaults)
        let stored = QueueThemeStore.current(defaults: defaults)
        #expect(stored.id == "dusk")
        #expect(stored.isPro)

        defaults.set("future-theme", forKey: QueueThemeStore.storageKey)
        #expect(QueueThemeStore.current(defaults: defaults).id == "forest")
    }
}
