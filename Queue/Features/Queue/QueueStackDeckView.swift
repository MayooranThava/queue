import SwiftUI
import QueueCore

/// The Queue tab's stack. Cards share the list's order: Now in front, up to
/// three cards tucked underneath, then a footer that opens List.
struct QueueStackDeckView: View {
    let tasks: [QueueTask]
    let focusSnapshot: FocusWidgetSnapshot?
    let focusAlertsDenied: Bool
    var onEdit: (QueueTask) -> Void
    var onOpenFocus: (QueueTask) -> Void
    var onOpenList: () -> Void
    var onStartFocus: (QueueTask) -> Void
    var onPause: (QueueTask) -> Void
    var onResume: (QueueTask) -> Void
    var onExtend: (QueueTask) -> Void
    var onComplete: (QueueTask) -> Void
    var onExpire: () -> Void
    var menu: (Int, QueueTask) -> QueueBlockMenu

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.queueAnimationIntensity) private var animationIntensity
    @Environment(\.queueCompanionVisible) private var companionVisible
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var nowHeight = CGFloat(StackDeckLayout.nowCardHeight)

    private var focusIsRunning: Bool {
        focusSnapshot?.session.state == .running
    }

    private var plainList: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var placements: [StackDeckLayout.Card] {
        StackDeckLayout.cards(
            taskCount: tasks.count,
            nowHeight: Double(nowHeight),
            focusIsRunning: focusIsRunning,
            plainList: plainList
        )
    }

    private var rows: [DeckRow] {
        placements.map { card in
            DeckRow(id: rowID(for: card), card: card)
        }
    }

    private var animationIdentity: [String] {
        var values = tasks.map(\.id.uuidString)
        if focusIsRunning {
            values.append("focus")
        }
        return values
    }

    private var deckAnimation: Animation {
        switch StackDeckLayout.motion(
            reduceMotion: reduceMotion,
            allowsMotion: animationIntensity.allowsMotion
        ) {
        case .spring:
            return .spring(duration: StackDeckLayout.springDuration)
        case .crossfade:
            return .easeInOut(duration: 0.2)
        }
    }

    var body: some View {
        Group {
            if plainList {
                plainListStack
            } else {
                deck
            }
        }
    }

    /// One stack. Later indexes sit further back, so zIndex falls as the index rises.
    private var deck: some View {
        ZStack(alignment: .top) {
            ForEach(rows) { row in
                deckCard(row)
                    .padding(.horizontal, CGFloat(row.card.inset))
                    .offset(y: CGFloat(row.card.y))
                    .zIndex(row.card.zIndex)
                    .accessibilitySortPriority(sortPriority(for: row.card))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: CGFloat(StackDeckLayout.stackHeight(of: placements)), alignment: .top)
        .geometryGroup()
        .animation(deckAnimation, value: animationIdentity)
        .onPreferenceChange(NowCardHeightKey.self) { newValue in
            guard newValue > 1, abs(newValue - nowHeight) > 0.5 else { return }
            nowHeight = newValue
        }
    }

    /// Largest accessibility sizes drop the overlap and show every task in order.
    private var plainListStack: some View {
        VStack(spacing: CGFloat(StackDeckLayout.plainSpacing)) {
            ForEach(rows) { row in
                plainCard(row)
                    .zIndex(row.card.zIndex)
                    .accessibilitySortPriority(sortPriority(for: row.card))
            }
        }
    }

    @ViewBuilder
    private func deckCard(_ row: DeckRow) -> some View {
        switch row.card.role {
        case .task(let index):
            if tasks.indices.contains(index) {
                if index == 0 {
                    nowCard(tasks[index], measure: true)
                } else {
                    peekCard(tasks[index], index: index, placement: row.card)
                }
            }
        case .footer(let hidden, let next):
            footerCard(hiddenCount: hidden, nextIndex: next, height: row.card.height)
        }
    }

    @ViewBuilder
    private func plainCard(_ row: DeckRow) -> some View {
        switch row.card.role {
        case .task(let index):
            if tasks.indices.contains(index) {
                if index == 0 {
                    nowCard(tasks[index], measure: false)
                } else {
                    plainRow(tasks[index], index: index)
                }
            }
        case .footer:
            EmptyView()
        }
    }

    private func nowCard(_ task: QueueTask, measure: Bool) -> some View {
        let live = focusSnapshot
        let cardMenu = menu(0, task)
        return nowFace(task: task, live: live)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(StackCardSurface(dim: 0, outlined: true, shadowed: true))
            .background {
                if measure {
                    GeometryReader { proxy in
                        Color.clear.preference(key: NowCardHeightKey.self, value: proxy.size.height)
                    }
                }
            }
            .modifier(QueueBlockInteractions(menu: cardMenu))
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: Text("Skip")) { cardMenu.onSkip() }
            .accessibilityAction(named: Text("Delete")) { cardMenu.onDelete() }
            .modifier(MoveToBottomAccessibilityAction(enabled: cardMenu.onMoveToBottom != nil) {
                cardMenu.onMoveToBottom?()
            })
    }

    private func nowFace(task: QueueTask, live: FocusWidgetSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NOW")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(QueueColors.primary)
                .accessibilityHidden(true)

            HStack(alignment: .center, spacing: QueueSpacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        onOpenFocus(task)
                    } label: {
                        Text(task.title)
                            .font(.system(.title, design: .rounded).weight(.semibold))
                            .foregroundStyle(QueueColors.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(QueueAccessibilityID.queueOpenFocus)
                    .accessibilityLabel(spoken(task, index: 0))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHint("Opens the full focus screen")
                    .accessibilitySortPriority(nowSortPriority)

                    if live == nil {
                        Text(meta(for: task))
                            .font(.subheadline)
                            .foregroundStyle(QueueColors.textSecondary)
                            .accessibilityHidden(true)
                    }
                }
                if companionVisible {
                    companionBadge(live: live)
                }
            }
            .padding(.top, 10)

            if let live {
                StackLiveFocusStatus(
                    snapshot: live,
                    task: task,
                    reduceMotion: reduceMotion || !animationIntensity.allowsMotion,
                    alertsDenied: focusAlertsDenied,
                    onExpire: onExpire
                )
                .padding(.top, 14)
                .accessibilitySortPriority(nowSortPriority)

                liveButtons(task: task, state: live.session.state)
                    .padding(.top, 12)
                    .accessibilitySortPriority(nowSortPriority)
            } else {
                Button(startTitle(for: task)) { onStartFocus(task) }
                    .buttonStyle(StackPrimaryButtonStyle())
                    .padding(.top, 16)
                    .accessibilityHint("Starts the countdown on this card")
                    .accessibilitySortPriority(nowSortPriority)
            }

            HStack(spacing: QueueSpacing.sm) {
                Button("Edit") { onEdit(task) }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(QueueColors.primary)
                    .accessibilityHint("Opens the editor for the active task")
                    .accessibilitySortPriority(nowSortPriority)
                Spacer(minLength: 0)
                Button {
                    menu(0, task).onSkip()
                } label: {
                    HStack(spacing: 2) {
                        Text("Skip")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(QueueColors.textSecondary)
                }
                .accessibilityHint("Skips this task")
                .accessibilitySortPriority(nowSortPriority)
            }
            .padding(.top, 6)
            .accessibilitySortPriority(nowSortPriority)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private func peekCard(_ task: QueueTask, index: Int, placement: StackDeckLayout.Card) -> some View {
        let cardMenu = menu(index, task)
        return VStack(spacing: 0) {
            Color.clear
                .frame(height: CGFloat(StackDeckLayout.tuck))
                .accessibilityHidden(true)
            peekFace(task, index: index)
                .frame(maxWidth: .infinity)
                .frame(height: CGFloat(StackDeckLayout.peekHeight))
        }
        .frame(height: CGFloat(placement.height))
        .modifier(StackCardSurface(dim: placement.dim, outlined: false, shadowed: false))
        .modifier(QueueBlockInteractions(menu: cardMenu))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(task, index: index))
        .modifier(PeekAccessibilityActions(menu: cardMenu))
    }

    private func peekFace(_ task: QueueTask, index: Int) -> some View {
        HStack(alignment: .center, spacing: QueueSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(QueueColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(meta(for: task))
                    .font(.subheadline)
                    .foregroundStyle(QueueColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: QueueSpacing.xs)
            Text("\(index + 1)")
                .font(.body.weight(.medium))
                .foregroundStyle(QueueColors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, QueueSpacing.md)
    }

    private func plainRow(_ task: QueueTask, index: Int) -> some View {
        let cardMenu = menu(index, task)
        return peekFace(task, index: index)
            .padding(.vertical, QueueSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(StackCardSurface(dim: 0, outlined: false, shadowed: false))
            .modifier(QueueBlockInteractions(menu: cardMenu))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(task, index: index))
            .modifier(PeekAccessibilityActions(menu: cardMenu))
    }

    private func footerCard(hiddenCount: Int, nextIndex: Int, height: Double) -> some View {
        let title = tasks.indices.contains(nextIndex) ? tasks[nextIndex].title : ""
        return Button(action: onOpenList) {
            Text(StackDeckLayout.footerTitle(hiddenCount: hiddenCount, nextTitle: title))
                .font(.subheadline)
                .foregroundStyle(QueueColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, QueueSpacing.md)
                .frame(height: CGFloat(height))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(StackDeckLayout.footerAccessibilityLabel(hiddenCount: hiddenCount, nextTitle: title))
        .accessibilityHint("Opens the list")
    }

    private func companionBadge(live: FocusWidgetSnapshot?) -> some View {
        CompanionAnimationView(
            state: companionState(live: live),
            reduceMotion: reduceMotion,
            compact: true
        )
        .frame(width: 40, height: 40)
        .frame(width: 52, height: 52)
        .background {
            Circle().strokeBorder(QueueColors.primary.opacity(0.85), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }

    private func companionState(live: FocusWidgetSnapshot?) -> CompanionVisualState {
        guard let live else { return .idle }
        switch live.session.state {
        case .running: return .working
        case .paused: return .paused
        case .expired: return .timerExpired
        default: return .working
        }
    }

    @ViewBuilder
    private func liveButtons(task: QueueTask, state: FocusTimerState) -> some View {
        VStack(spacing: QueueSpacing.xs) {
            HStack(spacing: QueueSpacing.xs) {
                switch state {
                case .paused:
                    Button("Resume") { onResume(task) }
                        .buttonStyle(StackSecondaryButtonStyle())
                case .running:
                    Button("Pause") { onPause(task) }
                        .buttonStyle(StackSecondaryButtonStyle())
                case .idle, .expired, .completed:
                    EmptyView()
                }
                if state == .running || state == .paused || state == .expired {
                    Button("+5 min") { onExtend(task) }
                        .buttonStyle(StackSecondaryButtonStyle())
                        .accessibilityLabel("Extend five minutes")
                }
            }
            if state == .running || state == .paused || state == .expired {
                Button("Done") { onComplete(task) }
                    .buttonStyle(StackPrimaryButtonStyle())
                    .accessibilityHint("Marks the task done and awards XP")
            }
        }
    }

    private func startTitle(for task: QueueTask) -> String {
        switch task.status {
        case .active, .paused, .expired:
            return "Continue focus"
        default:
            return "Start focus"
        }
    }

    private func meta(for task: QueueTask) -> String {
        let minutes = max(1, Int(task.estimatedDuration / 60))
        return "\(minutes) min · \(task.difficulty.displayName)"
    }

    private func spoken(_ task: QueueTask, index: Int) -> String {
        StackDeckLayout.accessibilityLabel(
            position: index + 1,
            total: tasks.count,
            title: task.title,
            detail: meta(for: task)
        )
    }

    /// Now's controls sit above every tucked card. Within the rest of the deck,
    /// higher values are read first so VoiceOver follows queue order.
    private var nowSortPriority: Double { 3_000 }

    private func sortPriority(for card: StackDeckLayout.Card) -> Double {
        if let index = card.taskIndex {
            return index == 0 ? nowSortPriority : Double(tasks.count - index)
        }
        return 0
    }

    private func rowID(for card: StackDeckLayout.Card) -> String {
        switch card.role {
        case .task(let index):
            guard tasks.indices.contains(index) else { return "task-\(index)" }
            return tasks[index].id.uuidString
        case .footer:
            return "footer"
        }
    }

    private struct DeckRow: Identifiable {
        let id: String
        let card: StackDeckLayout.Card
    }
}

private struct NowCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

/// Countdown on the Now card. Remaining time is read from the session timestamps.
private struct StackLiveFocusStatus: View {
    let snapshot: FocusWidgetSnapshot
    let task: QueueTask
    let reduceMotion: Bool
    let alertsDenied: Bool
    var onExpire: () -> Void

    @State private var didRequestExpiry = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 1 : 0.25)) { context in
            let remaining = snapshot.remaining(at: context.date)
            VStack(alignment: .leading, spacing: QueueSpacing.xs) {
                HStack(alignment: .center, spacing: QueueSpacing.sm) {
                    FocusCountdownRing(
                        progress: snapshot.progress(at: context.date),
                        isExpired: snapshot.session.state == .expired,
                        isPaused: snapshot.session.state == .paused,
                        reduceMotion: reduceMotion,
                        lineWidth: 2.5
                    )
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(FocusTimerFormatting.clock(remaining))
                            .font(.system(.title2, design: .rounded).weight(.medium).monospacedDigit())
                            .foregroundStyle(QueueColors.textPrimary)
                            .contentTransition(.numericText())
                            .accessibilityLabel("Time remaining \(FocusTimerFormatting.spoken(remaining))")

                        Text(statusCaption)
                            .font(.subheadline)
                            .foregroundStyle(QueueColors.textSecondary)
                    }
                }

                if alertsDenied {
                    Text("Focus alerts are off. You can turn them on in iOS Settings.")
                        .font(.caption)
                        .foregroundStyle(QueueColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .onChange(of: remaining) { _, newValue in
                guard newValue <= 0, snapshot.session.state == .running, !didRequestExpiry else { return }
                didRequestExpiry = true
                onExpire()
            }
        }
        .onChange(of: snapshot.session.state) { _, state in
            if state == .running {
                didRequestExpiry = false
            }
        }
    }

    private var statusCaption: String {
        let minutes = max(1, Int(task.estimatedDuration / 60))
        switch snapshot.session.state {
        case .paused:
            return "Paused · \(snapshot.difficultyDisplayName)"
        case .expired:
            return "Time’s up · finish when you’re ready"
        case .running:
            return "Focusing · \(snapshot.difficultyDisplayName) · \(minutes) min"
        default:
            return "\(minutes) min · \(task.difficulty.displayName)"
        }
    }
}

/// Fill, hairline, and shadow for one stack card.
/// Back cards darken with a black veil. They do not pick up a lighter tint,
/// because light-mode background is lighter than the card surface.
private struct StackCardSurface: ViewModifier {
    var dim: Double
    var outlined: Bool
    var shadowed: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(QueueColors.surface)
                shape.fill(Color.black.opacity(dim))
            }
            .clipShape(shape)
            .overlay {
                if outlined {
                    shape.strokeBorder(
                        QueueColors.textPrimary.opacity(hairlineOpacity),
                        lineWidth: contrast == .increased ? 1.5 : 1
                    )
                }
            }
            .compositingGroup()
            .shadow(
                color: shadowed ? Color.black.opacity(shadowOpacity) : .clear,
                radius: shadowed ? 16 : 0,
                x: 0,
                y: shadowed ? 8 : 0
            )
    }

    private var hairlineOpacity: Double {
        if contrast == .increased { return 0.55 }
        return colorScheme == .dark ? 0.18 : 0.12
    }

    private var shadowOpacity: Double {
        colorScheme == .dark ? 0.45 : 0.14
    }

    private static let cornerRadius: CGFloat = 22
}

private struct PeekAccessibilityActions: ViewModifier {
    let menu: QueueBlockMenu

    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: Text("Edit")) { menu.onEdit() }
            .accessibilityAction(named: Text("Skip")) { menu.onSkip() }
            .accessibilityAction(named: Text("Delete")) { menu.onDelete() }
            .modifier(MoveToBottomAccessibilityAction(enabled: menu.onMoveToBottom != nil) {
                menu.onMoveToBottom?()
            })
            .modifier(MoveAccessibilityAction(name: "Move up", action: menu.onMoveUp))
            .modifier(MoveAccessibilityAction(name: "Move down", action: menu.onMoveDown))
    }
}

private struct MoveAccessibilityAction: ViewModifier {
    let name: String
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.accessibilityAction(named: Text(name)) { action() }
        } else {
            content
        }
    }
}

private struct StackPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(QueueColors.onPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(QueueColors.primary)
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

private struct StackSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(QueueColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: QueueSpacing.minTouch)
            .background(
                RoundedRectangle(cornerRadius: QueueSpacing.cornerMinimal, style: .continuous)
                    .fill(QueueColors.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: QueueSpacing.cornerMinimal, style: .continuous)
                    .strokeBorder(QueueColors.textSecondary.opacity(0.45), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}
