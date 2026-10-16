import SwiftUI

enum QueueTypography {
    static func display(_ size: CGFloat = 40) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func title(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static func headline(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func body(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func caption(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    static func monoTimer(_ size: CGFloat = 56) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
            .monospacedDigit()
    }
}
