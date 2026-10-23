import Foundation
import Testing

struct QueuePaletteTests {
    private struct Slot: Hashable {
        var dark: Bool
        var highContrast: Bool
    }

    @Test func everyRoleHasLightDarkAndHighContrastColors() throws {
        let colors = try loadCatalog()
        let roles = [
            "Background", "Surface", "TextPrimary", "TextSecondary",
            "Primary", "OnPrimary", "Accent", "OnAccent", "Success", "Danger"
        ]
        #expect(Set(colors.keys) == Set(roles))
        for role in roles {
            let slots = colors[role] ?? [:]
            #expect(slots[Slot(dark: false, highContrast: false)] != nil, "\(role) light")
            #expect(slots[Slot(dark: true, highContrast: false)] != nil, "\(role) dark")
            #expect(slots[Slot(dark: false, highContrast: true)] != nil, "\(role) light high contrast")
            #expect(slots[Slot(dark: true, highContrast: true)] != nil, "\(role) dark high contrast")
        }
    }

    @Test func approvedLightAndDarkValuesMatchThePalette() throws {
        let colors = try loadCatalog()
        let approved: [String: (light: String, dark: String)] = [
            "Background": ("FAF7F0", "1A2617"),
            "Surface": ("EEF2EA", "263620"),
            "TextPrimary": ("1F2A1B", "FAF7F0"),
            "TextSecondary": ("566150", "B4C2AE"),
            "Primary": ("A9532A", "E0814F"),
            "OnPrimary": ("FAF7F0", "1A2617"),
            "Accent": ("E9A84E", "F0B85A"),
            "OnAccent": ("1F2A1B", "1A2617"),
            "Success": ("3D6B37", "8FC27E"),
            "Danger": ("A23B2E", "EC8A74")
        ]
        for (role, pair) in approved {
            #expect(colors[role]?[Slot(dark: false, highContrast: false)] == pair.light, role)
            #expect(colors[role]?[Slot(dark: true, highContrast: false)] == pair.dark, role)
        }
    }

    @Test func textOnFillMeetsContrastInEveryAppearance() throws {
        let colors = try loadCatalog()
        let slots = [
            Slot(dark: false, highContrast: false),
            Slot(dark: true, highContrast: false),
            Slot(dark: false, highContrast: true),
            Slot(dark: true, highContrast: true)
        ]
        let pairs = [
            ("TextPrimary", "Background"),
            ("TextPrimary", "Surface"),
            ("TextSecondary", "Background"),
            ("TextSecondary", "Surface"),
            ("OnPrimary", "Primary"),
            ("OnPrimary", "Danger"),
            ("OnAccent", "Accent"),
            ("Primary", "Background"),
            ("Primary", "Surface"),
            ("Success", "Background"),
            ("Success", "Surface"),
            ("Danger", "Background"),
            ("Danger", "Surface")
        ]
        for slot in slots {
            for (text, fill) in pairs {
                let ratio = try contrast(text: text, fill: fill, slot: slot, colors: colors)
                #expect(ratio >= 4.5, "\(text) on \(fill) \(slot) is \(ratio)")
            }
            // Honey is a fill in light mode (on-accent is the text). It is readable text on the dark column.
            if slot.dark {
                let onBackground = try contrast(text: "Accent", fill: "Background", slot: slot, colors: colors)
                let onSurface = try contrast(text: "Accent", fill: "Surface", slot: slot, colors: colors)
                #expect(onBackground >= 4.5)
                #expect(onSurface >= 4.5)
            }
        }
    }

    @Test func highContrastStrengthensTheTightPairs() throws {
        let colors = try loadCatalog()
        let pairs = [
            ("OnPrimary", "Primary"),
            ("Primary", "Surface"),
            ("TextSecondary", "Surface"),
            ("Success", "Surface"),
            ("Danger", "Surface")
        ]
        for (text, fill) in pairs {
            for dark in [false, true] {
                let base = Slot(dark: dark, highContrast: false)
                let boosted = Slot(dark: dark, highContrast: true)
                let ratio = try contrast(text: text, fill: fill, slot: boosted, colors: colors)
                let original = try contrast(text: text, fill: fill, slot: base, colors: colors)
                #expect(ratio + 0.01 >= original, "\(text) on \(fill) dark=\(dark)")
                #expect(ratio >= 5.5, "\(text) on \(fill) dark=\(dark) high contrast is \(ratio)")
            }
        }
    }

    @Test func appIconsAreOpaque1024Squares() throws {
        let root = repoRoot()
        let names = ["AppIcon.png", "AppIcon-Dark.png", "AppIcon-Tinted.png"]
        for name in names {
            let url = root
                .appendingPathComponent("Queue/Resources/Assets.xcassets/AppIcon.appiconset")
                .appendingPathComponent(name)
            let data = try Data(contentsOf: url)
            let header = try pngHeader(data)
            #expect(header.width == 1024, name)
            #expect(header.height == 1024, name)
            #expect(header.colorType == 2, "\(name) should have no alpha channel")
        }
    }

    private func contrast(
        text: String,
        fill: String,
        slot: Slot,
        colors: [String: [Slot: String]]
    ) throws -> Double {
        let textHex = try #require(colors[text]?[slot])
        let fillHex = try #require(colors[fill]?[slot])
        return contrastRatio(textHex, fillHex)
    }

    private func loadCatalog() throws -> [String: [Slot: String]] {
        let root = repoRoot().appendingPathComponent("Shared/QueueColors.xcassets")
        var colors: [String: [Slot: String]] = [:]
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for folder in folders where folder.pathExtension == "colorset" {
            let role = folder.deletingPathExtension().lastPathComponent
            let data = try Data(contentsOf: folder.appendingPathComponent("Contents.json"))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let entries = json?["colors"] as? [[String: Any]] ?? []
            var slots: [Slot: String] = [:]
            for entry in entries {
                let appearances = entry["appearances"] as? [[String: String]] ?? []
                let dark = appearances.contains { $0["appearance"] == "luminosity" && $0["value"] == "dark" }
                let highContrast = appearances.contains { $0["appearance"] == "contrast" && $0["value"] == "high" }
                let color = entry["color"] as? [String: Any]
                let components = color?["components"] as? [String: String] ?? [:]
                slots[Slot(dark: dark, highContrast: highContrast)] = try hex(components)
            }
            colors[role] = slots
        }
        return colors
    }

    private func hex(_ components: [String: String]) throws -> String {
        let red = try channel(components["red"])
        let green = try channel(components["green"])
        let blue = try channel(components["blue"])
        let alpha = Double(components["alpha"] ?? "0") ?? 0
        #expect(abs(alpha - 1) < 0.001)
        return String(format: "%02X%02X%02X", red, green, blue)
    }

    private func channel(_ raw: String?) throws -> Int {
        let value = try #require(raw)
        if value.lowercased().hasPrefix("0x") {
            return try #require(Int(value.dropFirst(2), radix: 16))
        }
        let unit = try #require(Double(value))
        return Int((unit * 255).rounded())
    }

    private func contrastRatio(_ lhs: String, _ rhs: String) -> Double {
        let lighter = max(relativeLuminance(lhs), relativeLuminance(rhs))
        let darker = min(relativeLuminance(lhs), relativeLuminance(rhs))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ hex: String) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let value = Int(hex, radix: 16) ?? 0
        let red = linear(Double((value >> 16) & 0xFF) / 255)
        let green = linear(Double((value >> 8) & 0xFF) / 255)
        let blue = linear(Double(value & 0xFF) / 255)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private func pngHeader(_ data: Data) throws -> (width: Int, height: Int, colorType: Int) {
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        #expect(Array(data.prefix(8)) == signature)
        #expect(data.count > 24)
        func word(_ offset: Int) -> Int {
            data[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
        }
        #expect(word(8) == 13)
        #expect(Array(data[12..<16]) == Array("IHDR".utf8))
        return (word(16), word(20), Int(data[25]))
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
