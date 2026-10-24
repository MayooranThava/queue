import Foundation

/// Geometry for the Queue stack.
///
/// The deck is the head of the same ordered queue List and the widget show.
/// Now sits in front. Each card behind is tucked under the one above it and
/// only its lower strip is visible. A footer closes the stack when the queue
/// is longer than that window, so the last card is never clipped.
public enum StackDeckLayout {
    /// Visible strip of each card tucked under the card in front.
    public static let peekHeight: Double = 58
    /// Extra horizontal inset, per step back from Now.
    public static let insetStep: Double = 4
    /// How far a back card continues up under the card in front of it.
    public static let tuck: Double = 18
    /// Now plus three cards behind.
    public static let maxVisibleTasks = 4
    /// Cards tucked behind Now while the queue is idle.
    public static let maxBehindCards = 3
    /// Cards tucked behind Now while focus is running.
    public static let focusingBehindCards = 2
    /// Content height of the Now card at the default text size. The view
    /// measures the real card and passes that in; this is the fallback.
    public static let nowCardHeight: Double = 232
    /// Fully visible row under the last peek. It is the stack's bottom edge.
    public static let footerHeight: Double = 44
    /// How much darker each step back from Now is. Larger is darker.
    public static let dimStep: Double = 0.06
    /// Added on top of `dimStep` for every card behind Now while focus runs.
    public static let focusDimBoost: Double = 0.10
    /// Gap between full rows when accessibility sizes drop the overlap.
    public static let plainSpacing: Double = 12
    /// Height of a non-Now row in that plain list.
    public static let plainRowHeight: Double = 88
    /// Deck motion. The view uses `.spring(duration: springDuration)`.
    public static let springDuration: Double = 0.35

    public enum Motion: Equatable, Sendable {
        case spring
        case crossfade
    }

    public struct Card: Equatable, Sendable {
        public enum Role: Equatable, Sendable {
            /// Index into the queue List is already showing, starting at Now.
            case task(index: Int)
            /// Tasks not given a face. `nextIndex` is the first of them.
            case footer(hiddenCount: Int, nextIndex: Int)
        }

        public var role: Role
        /// Top of this card's frame in the stack.
        public var y: Double
        /// Extra inset from the stack's leading and trailing edges.
        public var inset: Double
        /// Higher draws in front. Now is always strictly the greatest.
        public var zIndex: Double
        /// 0 leaves the surface untouched. Larger darkens the fill. Text is not faded.
        public var dim: Double
        /// Frame height. The tucked strip is included; the container must fit all of it.
        public var height: Double

        public var taskIndex: Int? {
            if case .task(let index) = role { return index }
            return nil
        }

        public var isNow: Bool { taskIndex == 0 }

        public var footer: (hiddenCount: Int, nextIndex: Int)? {
            if case .footer(let hiddenCount, let nextIndex) = role {
                return (hiddenCount, nextIndex)
            }
            return nil
        }
    }

    public static func motion(reduceMotion: Bool, allowsMotion: Bool) -> Motion {
        if reduceMotion || !allowsMotion { return .crossfade }
        return .spring
    }

    /// Darkening of a card `depth` steps behind Now. Depth 0 is Now and stays at 0.
    /// Focusing adds `focusDimBoost` so the cards behind recede further.
    /// The value is a fraction of a dark veil. It never lightens the surface.
    public static func dim(depth: Int, focusIsRunning: Bool) -> Double {
        let steps = max(0, depth)
        guard steps > 0 else { return 0 }
        let base = dimStep * Double(steps)
        let amount = focusIsRunning ? base + focusDimBoost : base
        return min(0.45, amount)
    }

    public static func inset(depth: Int) -> Double {
        insetStep * Double(max(0, depth))
    }

    /// Placements from the front of the queue to the back.
    ///
    /// `plainList` is the accessibility-size layout: every task, no tuck,
    /// no footer, and a gap instead of an overlap. Focus does not cap it.
    public static func cards(
        taskCount: Int,
        nowHeight: Double = nowCardHeight,
        focusIsRunning: Bool = false,
        plainList: Bool = false
    ) -> [Card] {
        guard taskCount > 0 else { return [] }
        let now = finitePositive(nowHeight, fallback: nowCardHeight)
        if plainList {
            return plainCards(taskCount: taskCount, nowHeight: now)
        }
        return deckCards(taskCount: taskCount, nowHeight: now, focusIsRunning: focusIsRunning)
    }

    public static func stackHeight(of cards: [Card]) -> Double {
        cards.map { $0.y + $0.height }.max() ?? 0
    }

    public static func accessibilityLabel(position: Int, total: Int, title: String, detail: String) -> String {
        "Task \(position) of \(total), \(title), \(detail)"
    }

    public static func footerTitle(hiddenCount: Int, nextTitle: String) -> String {
        "+\(hiddenCount) more · \(nextTitle)"
    }

    public static func footerAccessibilityLabel(hiddenCount: Int, nextTitle: String) -> String {
        let lead = hiddenCount == 1 ? "1 more task" : "\(hiddenCount) more tasks"
        return "\(lead), \(nextTitle)"
    }

    // MARK: - Deck

    private static func deckCards(taskCount: Int, nowHeight: Double, focusIsRunning: Bool) -> [Card] {
        let behind = min(
            focusIsRunning ? focusingBehindCards : maxBehindCards,
            max(0, taskCount - 1)
        )
        let visible = 1 + behind
        let hidden = taskCount - visible
        let slots = visible + (hidden > 0 ? 1 : 0)
        var cards: [Card] = []
        cards.append(
            Card(
                role: .task(index: 0),
                y: 0,
                inset: inset(depth: 0),
                zIndex: Double(slots),
                dim: dim(depth: 0, focusIsRunning: focusIsRunning),
                height: nowHeight
            )
        )
        if behind > 0 {
            let backHeight = peekHeight + tuck
            for depth in 1...behind {
                cards.append(
                    Card(
                        role: .task(index: depth),
                        y: nowHeight + Double(depth - 1) * peekHeight - tuck,
                        inset: inset(depth: depth),
                        zIndex: Double(slots - depth),
                        dim: dim(depth: depth, focusIsRunning: focusIsRunning),
                        height: backHeight
                    )
                )
            }
        }
        if hidden > 0 {
            cards.append(
                Card(
                    role: .footer(hiddenCount: hidden, nextIndex: visible),
                    y: nowHeight + Double(behind) * peekHeight,
                    inset: 0,
                    zIndex: Double(slots - visible),
                    dim: 0,
                    height: footerHeight
                )
            )
        }
        return cards
    }

    private static func plainCards(taskCount: Int, nowHeight: Double) -> [Card] {
        var cards: [Card] = []
        var y = 0.0
        for index in 0..<taskCount {
            let height = index == 0 ? nowHeight : plainRowHeight
            cards.append(
                Card(
                    role: .task(index: index),
                    y: y,
                    inset: 0,
                    zIndex: Double(taskCount - index),
                    dim: 0,
                    height: height
                )
            )
            y += height + plainSpacing
        }
        return cards
    }

    private static func finitePositive(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite, value > 0 else { return fallback }
        return value
    }
}
