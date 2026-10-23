import SwiftUI
import UIKit
import QueueCore

/// Semantic color roles. Light and dark values come from the selected `QueueTheme`.
/// Forest Increase Contrast still comes from `QueueColors.xcassets`.
enum QueueColorRole: String, CaseIterable {
    case background = "Background"
    case surface = "Surface"
    case textPrimary = "TextPrimary"
    case textSecondary = "TextSecondary"
    case primary = "Primary"
    case accent = "Accent"
    case success = "Success"
    case danger = "Danger"
    case onPrimary = "OnPrimary"
    case onAccent = "OnAccent"

    var paletteRole: QueuePaletteRole {
        switch self {
        case .background: return .background
        case .surface: return .surface
        case .textPrimary: return .textPrimary
        case .textSecondary: return .textSecondary
        case .primary: return .primary
        case .accent: return .accent
        case .success: return .success
        case .danger: return .danger
        case .onPrimary: return .onPrimary
        case .onAccent: return .onAccent
        }
    }
}

private struct QueueThemeKey: EnvironmentKey {
    static let defaultValue = QueueTheme.forest
}

extension EnvironmentValues {
    var queueTheme: QueueTheme {
        get { self[QueueThemeKey.self] }
        set { self[QueueThemeKey.self] = newValue }
    }
}

/// Adaptive theme colour. Resolves against the current theme and appearance.
struct QueueColorStyle: ShapeStyle {
    var role: QueueColorRole
    var opacity: Double = 1
    var fixedScheme: ColorScheme? = nil
    /// Bumped when the saved theme changes so SwiftUI treats the style as new.
    var themeID: String

    func opacity(_ amount: Double) -> QueueColorStyle {
        var copy = self
        copy.opacity *= amount
        return copy
    }

    func resolve(in environment: EnvironmentValues) -> Color {
        let scheme = fixedScheme ?? environment.colorScheme
        let increased = environment.colorSchemeContrast == .increased
        return QueueColors.concrete(
            role,
            theme: environment.queueTheme,
            scheme: scheme,
            increasedContrast: increased
        )
        .opacity(opacity)
    }
}

/// Honey is reward. In light mode it is only a badge fill under dark text.
/// Strokes, lines, and bare text use primary there, and honey in dark mode.
struct QueueRewardMarkStyle: ShapeStyle {
    var themeID: String

    func resolve(in environment: EnvironmentValues) -> Color {
        let role: QueueColorRole = environment.colorScheme == .dark ? .accent : .primary
        return QueueColorStyle(role: role, themeID: themeID).resolve(in: environment)
    }
}

enum QueueColors {
    static var background: QueueColorStyle { style(.background) }
    static var surface: QueueColorStyle { style(.surface) }
    static var textPrimary: QueueColorStyle { style(.textPrimary) }
    static var textSecondary: QueueColorStyle { style(.textSecondary) }
    static var primary: QueueColorStyle { style(.primary) }
    static var accent: QueueColorStyle { style(.accent) }
    static var success: QueueColorStyle { style(.success) }
    static var danger: QueueColorStyle { style(.danger) }
    static var onPrimary: QueueColorStyle { style(.onPrimary) }
    static var onAccent: QueueColorStyle { style(.onAccent) }
    static var rewardMark: QueueRewardMarkStyle {
        QueueRewardMarkStyle(themeID: QueueThemeStore.current().id)
    }

    /// Even stack rows use the card surface; odd rows sit on the background.
    static func stackBlock(index: Int) -> QueueColorStyle {
        index.isMultiple(of: 2) ? surface : background
    }

    /// Pins light or dark. Swipe actions use the light primary and success fills.
    static func fixed(_ role: QueueColorRole, style: UIUserInterfaceStyle) -> Color {
        let scheme: ColorScheme = style == .dark ? .dark : .light
        let increased = UITraitCollection.current.accessibilityContrast == .high
        return concrete(
            role,
            theme: QueueThemeStore.current(),
            scheme: scheme,
            increasedContrast: increased
        )
    }

    /// Dark-column color for widgets, Live Activity, and the Watch Smart Stack.
    /// The provider reads the shared theme when the surface is rendered.
    static func dark(_ role: QueueColorRole) -> Color {
        Color(uiColor: UIColor { traits in
            let increased = traits.accessibilityContrast == .high
            return uiColor(
                role,
                theme: QueueThemeStore.current(),
                scheme: .dark,
                increasedContrast: increased
            )
        })
    }

    static func concrete(
        _ role: QueueColorRole,
        theme: QueueTheme,
        scheme: ColorScheme,
        increasedContrast: Bool
    ) -> Color {
        Color(uiColor: uiColor(role, theme: theme, scheme: scheme, increasedContrast: increasedContrast))
    }

    private static func style(_ role: QueueColorRole, scheme: ColorScheme? = nil) -> QueueColorStyle {
        QueueColorStyle(role: role, fixedScheme: scheme, themeID: QueueThemeStore.current().id)
    }

    private static func uiColor(
        _ role: QueueColorRole,
        theme: QueueTheme,
        scheme: ColorScheme,
        increasedContrast: Bool
    ) -> UIColor {
        if theme.id == QueueTheme.forest.id,
           let catalog = forestCatalogColor(role, scheme: scheme, increasedContrast: increasedContrast) {
            return catalog
        }
        let rgb = theme.resolved(role.paletteRole, dark: scheme == .dark, increasedContrast: increasedContrast)
        return UIColor(rgb)
    }

    /// Forest stays on the shared catalog so Increase Contrast matches the shipped variants.
    private static func forestCatalogColor(
        _ role: QueueColorRole,
        scheme: ColorScheme,
        increasedContrast: Bool
    ) -> UIColor? {
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light),
            UITraitCollection(accessibilityContrast: increasedContrast ? .high : .normal)
        ])
        guard let named = UIColor(named: role.rawValue, in: .main, compatibleWith: traits) else {
            return nil
        }
        return named.resolvedColor(with: traits)
    }
}

extension Color {
    init(_ rgb: QueueRGB) {
        self.init(
            .sRGB,
            red: Double(rgb.red) / 255,
            green: Double(rgb.green) / 255,
            blue: Double(rgb.blue) / 255,
            opacity: 1
        )
    }
}

extension UIColor {
    convenience init(_ rgb: QueueRGB) {
        self.init(
            red: CGFloat(rgb.red) / 255,
            green: CGFloat(rgb.green) / 255,
            blue: CGFloat(rgb.blue) / 255,
            alpha: 1
        )
    }
}

/// Full-screen background that follows the selected theme and ignores the safe area.
struct QueueThemeBackground: View {
    @Environment(\.queueTheme) private var queueTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Rectangle()
            .fill(
                QueueColors.concrete(
                    .background,
                    theme: queueTheme,
                    scheme: colorScheme,
                    increasedContrast: contrast == .increased
                )
            )
            .ignoresSafeArea()
    }
}
