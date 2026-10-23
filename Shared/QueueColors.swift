import SwiftUI
import UIKit

/// Semantic color roles from the approved Queue palette.
/// Light and dark values, plus Increase Contrast variants, live in `QueueColors.xcassets`.
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
}

enum QueueColors {
    static var background: Color { adaptive(.background) }
    static var surface: Color { adaptive(.surface) }
    static var textPrimary: Color { adaptive(.textPrimary) }
    static var textSecondary: Color { adaptive(.textSecondary) }
    static var primary: Color { adaptive(.primary) }
    static var accent: Color { adaptive(.accent) }
    static var success: Color { adaptive(.success) }
    static var danger: Color { adaptive(.danger) }
    static var onPrimary: Color { adaptive(.onPrimary) }
    static var onAccent: Color { adaptive(.onAccent) }

    /// Even stack rows use the card surface; odd rows sit on the background.
    static func stackBlock(index: Int) -> Color {
        index.isMultiple(of: 2) ? surface : background
    }

    static func adaptive(_ role: QueueColorRole) -> Color {
        Color(role.rawValue, bundle: .main)
    }

    /// Dark-column color for Focus, widgets, and Live Activities.
    /// Increase Contrast still follows the current trait environment.
    static func dark(_ role: QueueColorRole) -> Color {
        fixed(role, style: .dark)
    }

    /// Pins light or dark while keeping the current Increase Contrast setting.
    /// Swipe actions use the light primary/success fills because their labels stay white.
    static func fixed(_ role: QueueColorRole, style: UIUserInterfaceStyle) -> Color {
        Color(uiColor: resolved(role, style: style))
    }

    private static func resolved(_ role: QueueColorRole, style: UIUserInterfaceStyle) -> UIColor {
        UIColor { traits in
            let combined = UITraitCollection(traitsFrom: [
                traits,
                UITraitCollection(userInterfaceStyle: style)
            ])
            guard let named = UIColor(named: role.rawValue, in: .main, compatibleWith: combined) else {
                return .clear
            }
            return named.resolvedColor(with: combined)
        }
    }
}
