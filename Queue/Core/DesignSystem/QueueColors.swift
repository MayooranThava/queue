import SwiftUI

/// Queue visual language: warm ivory, sage, charcoal focus, restrained chartreuse rewards.
enum QueueColors {
    static let ivory = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let ivoryDark = Color(red: 0.12, green: 0.12, blue: 0.11)
    static let sage = Color(red: 0.78, green: 0.84, blue: 0.76)
    static let sageDeep = Color(red: 0.45, green: 0.55, blue: 0.48)
    static let charcoal = Color(red: 0.14, green: 0.15, blue: 0.16)
    static let charcoalElevated = Color(red: 0.20, green: 0.21, blue: 0.22)
    static let ink = Color(red: 0.16, green: 0.17, blue: 0.18)
    static let inkSecondary = Color(red: 0.40, green: 0.42, blue: 0.40)
    static let reward = Color(red: 0.72, green: 0.82, blue: 0.28)
    static let rewardDeep = Color(red: 0.55, green: 0.65, blue: 0.18)
    static let dangerSoft = Color(red: 0.75, green: 0.45, blue: 0.38)

    static var background: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(QueueColors.ivoryDark)
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
                ? UIColor(white: 0.72, alpha: 1)
                : UIColor(QueueColors.inkSecondary)
        })
    }

    static var secondarySurface: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(QueueColors.charcoalElevated)
                : UIColor(QueueColors.sage).withAlphaComponent(0.45)
        })
    }
}
