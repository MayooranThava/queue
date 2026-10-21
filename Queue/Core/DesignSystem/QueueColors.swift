import SwiftUI

/// Queue visual language: forest-green chrome (matching the App Icon), ivory/cream
/// surfaces, sage + terracotta accents, restrained chartreuse rewards.
enum QueueColors {
    static let ivory = Color(red: 0.98, green: 0.97, blue: 0.94)
    /// Dark forest green from the App Icon background — used for app edges / chrome.
    static let forest = Color(red: 38 / 255, green: 54 / 255, blue: 32 / 255)
    static let forestElevated = Color(red: 52 / 255, green: 72 / 255, blue: 44 / 255)
    static let forestDeep = Color(red: 24 / 255, green: 36 / 255, blue: 20 / 255)
    static let sage = Color(red: 0.78, green: 0.84, blue: 0.76)
    static let sageDeep = Color(red: 0.45, green: 0.55, blue: 0.48)
    static let terracotta = Color(red: 0.84, green: 0.54, blue: 0.33)
    static let charcoal = Color(red: 0.14, green: 0.15, blue: 0.16)
    static let charcoalElevated = Color(red: 0.20, green: 0.21, blue: 0.22)
    static let ink = Color(red: 0.16, green: 0.17, blue: 0.18)
    static let inkSecondary = Color(red: 0.40, green: 0.42, blue: 0.40)
    static let reward = Color(red: 0.72, green: 0.82, blue: 0.28)
    static let rewardDeep = Color(red: 0.55, green: 0.65, blue: 0.18)
    static let dangerSoft = Color(red: 0.75, green: 0.45, blue: 0.38)

    /// Kept for call sites that previously used the near-black dark chrome.
    static let ivoryDark = forest

    static var background: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(QueueColors.forest)
                : UIColor(QueueColors.ivory)
        })
    }

    static var primaryText: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(QueueColors.ivory)
                : UIColor(QueueColors.ink)
        })
    }

    static var secondaryText: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(QueueColors.sage).withAlphaComponent(0.85)
                : UIColor(QueueColors.inkSecondary)
        })
    }

    static var secondarySurface: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(QueueColors.forestElevated)
                : UIColor(QueueColors.sage).withAlphaComponent(0.45)
        })
    }

    /// Alternating flush shades for the Weekstack-inspired queue stack.
    static func stackBlock(index: Int) -> Color {
        Color(uiColor: UIColor { traits in
            let even = index.isMultiple(of: 2)
            if traits.userInterfaceStyle == .dark {
                return even
                    ? UIColor(QueueColors.forestElevated)
                    : UIColor(QueueColors.forestDeep)
            }
            return even
                ? UIColor(QueueColors.sage).withAlphaComponent(0.55)
                : UIColor(QueueColors.sage).withAlphaComponent(0.32)
        })
    }
}
