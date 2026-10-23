import Foundation

/// One sRGB colour. Themes store these instead of asset-catalog names so widgets
/// and the app can share the same values through the App Group.
public struct QueueRGB: Equatable, Hashable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        precondition(cleaned.count == 6, "Expected RRGGBB hex, got \(hex)")
        guard let value = UInt32(cleaned, radix: 16) else {
            preconditionFailure("Expected RRGGBB hex, got \(hex)")
        }
        red = UInt8((value >> 16) & 0xFF)
        green = UInt8((value >> 8) & 0xFF)
        blue = UInt8(value & 0xFF)
    }

    public var hex: String {
        String(format: "%02X%02X%02X", red, green, blue)
    }

    /// Moves this colour `fraction` of the way toward `other` (0 stays put, 1 arrives).
    public func mixed(toward other: QueueRGB, fraction: Double) -> QueueRGB {
        let amount = min(max(fraction, 0), 1)
        func channel(_ start: UInt8, _ end: UInt8) -> UInt8 {
            let value = Double(start) + (Double(end) - Double(start)) * amount
            return UInt8(min(255, max(0, value.rounded())))
        }
        return QueueRGB(
            red: channel(red, other.red),
            green: channel(green, other.green),
            blue: channel(blue, other.blue)
        )
    }

    public var relativeLuminance: Double {
        func linear(_ channel: UInt8) -> Double {
            let value = Double(channel) / 255
            if value <= 0.04045 {
                return value / 12.92
            }
            return pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2 contrast ratio. Order does not matter.
    public func contrastRatio(against other: QueueRGB) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

public enum QueuePaletteRole: String, CaseIterable, Sendable {
    case background
    case surface
    case textPrimary
    case textSecondary
    case primary
    case onPrimary
    case accent
    case onAccent
    case success
    case danger
}

/// The ten roles every theme has in light and in dark.
/// Honey (`accent`) is reward, green is success, red is danger.
public struct QueuePalette: Equatable, Hashable, Sendable {
    public let background: QueueRGB
    public let surface: QueueRGB
    public let textPrimary: QueueRGB
    public let textSecondary: QueueRGB
    public let primary: QueueRGB
    public let onPrimary: QueueRGB
    public let accent: QueueRGB
    public let onAccent: QueueRGB
    public let success: QueueRGB
    public let danger: QueueRGB

    public init(
        background: QueueRGB,
        surface: QueueRGB,
        textPrimary: QueueRGB,
        textSecondary: QueueRGB,
        primary: QueueRGB,
        onPrimary: QueueRGB,
        accent: QueueRGB,
        onAccent: QueueRGB,
        success: QueueRGB,
        danger: QueueRGB
    ) {
        self.background = background
        self.surface = surface
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.primary = primary
        self.onPrimary = onPrimary
        self.accent = accent
        self.onAccent = onAccent
        self.success = success
        self.danger = danger
    }

    public func color(for role: QueuePaletteRole) -> QueueRGB {
        switch role {
        case .background: return background
        case .surface: return surface
        case .textPrimary: return textPrimary
        case .textSecondary: return textSecondary
        case .primary: return primary
        case .onPrimary: return onPrimary
        case .accent: return accent
        case .onAccent: return onAccent
        case .success: return success
        case .danger: return danger
        }
    }
}

/// A named light and dark palette. `isPro` is a label for later; every theme is selectable.
public struct QueueTheme: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let isPro: Bool
    public let light: QueuePalette
    public let dark: QueuePalette

    public init(id: String, name: String, isPro: Bool, light: QueuePalette, dark: QueuePalette) {
        self.id = id
        self.name = name
        self.isPro = isPro
        self.light = light
        self.dark = dark
    }

    /// Increase Contrast for themes other than Forest.
    /// Secondary text moves 10% toward primary text. Forest keeps the catalog variants.
    public func resolved(_ role: QueuePaletteRole, dark: Bool, increasedContrast: Bool) -> QueueRGB {
        var palette = dark ? self.dark : self.light
        if increasedContrast, id != Self.forest.id {
            palette = QueuePalette(
                background: palette.background,
                surface: palette.surface,
                textPrimary: palette.textPrimary,
                textSecondary: palette.textSecondary.mixed(toward: palette.textPrimary, fraction: 0.10),
                primary: palette.primary,
                onPrimary: palette.onPrimary,
                accent: palette.accent,
                onAccent: palette.onAccent,
                success: palette.success,
                danger: palette.danger
            )
        }
        return palette.color(for: role)
    }

    public static func theme(id: String?) -> QueueTheme {
        guard let id, let match = all.first(where: { $0.id == id }) else {
            return .forest
        }
        return match
    }

    public static let all: [QueueTheme] = [.forest, .harbor, .lagoon, .mocha, .dusk, .cloud]

    /// Default free theme.
    /// Success and danger are the approved colour-vision pair so the two stay
    /// apart under protanopia and deuteranopia.
    public static let forest = QueueTheme(
        id: "forest",
        name: "Forest",
        isPro: false,
        light: QueuePalette(
            background: "FAF7F0",
            surface: "EEF2EA",
            textPrimary: "1F2A1B",
            textSecondary: "566150",
            primary: "A9532A",
            onPrimary: "FAF7F0",
            accent: "E9A84E",
            onAccent: "1F2A1B",
            success: "34794B",
            danger: "8F2A1E"
        ),
        dark: QueuePalette(
            background: "1A2617",
            surface: "263620",
            textPrimary: "FAF7F0",
            textSecondary: "B4C2AE",
            primary: "E0814F",
            onPrimary: "1A2617",
            accent: "F0B85A",
            onAccent: "1A2617",
            success: "A3E0AB",
            danger: "EB8370"
        )
    )

    public static let harbor = QueueTheme(
        id: "harbor",
        name: "Harbor",
        isPro: false,
        light: QueuePalette(
            background: "F5F7FA",
            surface: "E6ECF3",
            textPrimary: "16202C",
            textSecondary: "4E5B6A",
            primary: "2F5D8A",
            onPrimary: "FFFFFF",
            accent: "E9A84E",
            onAccent: "16202C",
            success: "2E6B55",
            danger: "9C3321"
        ),
        dark: QueuePalette(
            background: "121A24",
            surface: "1C2733",
            textPrimary: "F2F5F8",
            textSecondary: "A9B6C4",
            primary: "86AEDA",
            onPrimary: "121A24",
            accent: "F0B85A",
            onAccent: "121A24",
            success: "7EC8A9",
            danger: "E07D6C"
        )
    )

    public static let lagoon = QueueTheme(
        id: "lagoon",
        name: "Lagoon",
        isPro: true,
        light: QueuePalette(
            background: "F4F8F7",
            surface: "E3EEEB",
            textPrimary: "142624",
            textSecondary: "4A5F5B",
            primary: "1F6F6B",
            onPrimary: "FFFFFF",
            accent: "E7A64C",
            onAccent: "142624",
            success: "2F6F41",
            danger: "8A1A14"
        ),
        dark: QueuePalette(
            background: "0F2221",
            surface: "183230",
            textPrimary: "F1F7F5",
            textSecondary: "A6BFBA",
            primary: "62C0B6",
            onPrimary: "0F2221",
            accent: "F0B85A",
            onAccent: "0F2221",
            success: "A7E2AC",
            danger: "EB8370"
        )
    )

    public static let mocha = QueueTheme(
        id: "mocha",
        name: "Mocha",
        isPro: true,
        light: QueuePalette(
            background: "FAF5F0",
            surface: "F1E7DE",
            textPrimary: "2B1F18",
            textSecondary: "66554A",
            primary: "865A44",
            onPrimary: "FAF5F0",
            accent: "EDB45A",
            onAccent: "2B1F18",
            success: "2F6F57",
            danger: "972C20"
        ),
        dark: QueuePalette(
            background: "1F1712",
            surface: "2C211A",
            textPrimary: "F7EFE8",
            textSecondary: "C2B1A4",
            primary: "F0A884",
            onPrimary: "1F1712",
            accent: "F2C063",
            onAccent: "1F1712",
            success: "97D3B1",
            danger: "EB8675"
        )
    )

    public static let dusk = QueueTheme(
        id: "dusk",
        name: "Dusk",
        isPro: true,
        light: QueuePalette(
            background: "F7F5FA",
            surface: "ECE7F3",
            textPrimary: "1E1A2B",
            textSecondary: "585266",
            primary: "5B4B8A",
            onPrimary: "FFFFFF",
            accent: "E9A84E",
            onAccent: "1E1A2B",
            success: "2E6B55",
            danger: "8F241E"
        ),
        dark: QueuePalette(
            background: "17142A",
            surface: "231F38",
            textPrimary: "F4F2FA",
            textSecondary: "B5AECA",
            primary: "AB9EE2",
            onPrimary: "17142A",
            accent: "F0B85A",
            onAccent: "17142A",
            success: "88D7BA",
            danger: "ED8782"
        )
    )

    /// Free neutral theme: warm off-white in light mode, true black in dark mode.
    public static let cloud = QueueTheme(
        id: "cloud",
        name: "Cloud",
        isPro: false,
        light: QueuePalette(
            background: "F0EEE9",
            surface: "E3E0D9",
            textPrimary: "1C1C1A",
            textSecondary: "54524D",
            primary: "3D4A57",
            onPrimary: "FFFFFF",
            accent: "E6A64E",
            onAccent: "1C1C1A",
            success: "2F6F54",
            danger: "8F2F1E"
        ),
        dark: QueuePalette(
            background: "000000",
            surface: "161616",
            textPrimary: "F0EEE9",
            textSecondary: "A8A59E",
            primary: "C9D3DD",
            onPrimary: "000000",
            accent: "F0B85A",
            onAccent: "000000",
            success: "86CBA4",
            danger: "E07D6C"
        )
    )
}

extension QueuePalette {
    init(
        background: String,
        surface: String,
        textPrimary: String,
        textSecondary: String,
        primary: String,
        onPrimary: String,
        accent: String,
        onAccent: String,
        success: String,
        danger: String
    ) {
        self.init(
            background: QueueRGB(hex: background),
            surface: QueueRGB(hex: surface),
            textPrimary: QueueRGB(hex: textPrimary),
            textSecondary: QueueRGB(hex: textSecondary),
            primary: QueueRGB(hex: primary),
            onPrimary: QueueRGB(hex: onPrimary),
            accent: QueueRGB(hex: accent),
            onAccent: QueueRGB(hex: onAccent),
            success: QueueRGB(hex: success),
            danger: QueueRGB(hex: danger)
        )
    }
}

/// App Group store for the selected theme. The app, widgets, Live Activity, and
/// Watch Smart Stack read this same key.
public enum QueueThemeStore {
    public static let storageKey = "queue.theme.id"

    public static func current(defaults: UserDefaults = AppGroupDefaults.shared) -> QueueTheme {
        QueueTheme.theme(id: defaults.string(forKey: storageKey))
    }

    public static func save(_ theme: QueueTheme, defaults: UserDefaults = AppGroupDefaults.shared) {
        defaults.set(theme.id, forKey: storageKey)
    }
}
