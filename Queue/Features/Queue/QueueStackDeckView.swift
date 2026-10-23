import SwiftUI
import QueueCore

/// Wallet-style stack for the Queue tab. List mode does not use this view.
/// Tapping a peek expands that task in place. It does not reorder the queue.
struct QueueStackDeckView: View {
    let tasks: [QueueTask]
    let focusSnapshot: FocusWidgetSnapshot?
    let focusAlertsDenied: Bool
    var onEdit: (QueueTask) -> Void
    var onOpenFocus: (QueueTask) -> Void
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .headline) private var peekHeight = CGFloat(StackDeckLayout.basePeekHeight)

    @State private var expandedTaskID: UUID?

    private var ids: [UUID] { tasks.map(\.id) }

    private var expandedIndex: Int {
        StackDeckLayout.expandedIndex(matching: expandedTaskID, in: ids)
    }

    private var deckMotion: StackDeckLayout.Motion {
        StackDeckLayout.motion(
            reduceMotion: reduceMotion,
            allowsMotion: animationIntensity.allowsMotion
        )
    }

    private var deckAnimation: Animation {
        switch deckMotion {
        case .spring:
            return .spring(response: 0.45, dampingFraction: 0.84)
        case .crossfade:
            return .easeInOut(duration: 0.2)
        }
    }

    private var focusIsRunning: Bool {
        focusSnapshot?.session.state == .running
    }

    /// Index of the full card inside the visible deck, not the queue index.
    private var expandedSlot: Int {
        rows.firstIndex(where: { $0.card.isExpanded }) ?? 0
    }

    var body: some View {
        // Every card is as tall as the expanded card. Horizontal padding is only
        // there so the light-mode shadow survives the clip that hides each card's
        // lower body; the negative padding gives that width back to the queue.
        WalletStackLayout(expandedSlot: CGFloat(expandedSlot), peekHeight: peekHeight) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { slot, row in
                // Later cards paint above earlier ones so each top strip is all that shows.
                deckSlot(row.card)
                    .zIndex(Double(slot))
            }
        }
        .padding(.horizontal, QueueSpacing.md)
        .clipped()
        .padding(.horizontal, -QueueSpacing.md)
        .geometryGroup()
        .animation(.easeInOut(duration: 0.2), value: focusIsRunning)
        .simultaneousGesture(flipGesture)
        .onChange(of: ids) { _, newIDs in
            if let expandedTaskID, !newIDs.contains(expandedTaskID) {
                self.expandedTaskID = nil
            }
        }
    }

    private var rows: [DeckRow] {
        let layout = StackDeckLayout.cards(taskCount: tasks.count, expandedIndex: expandedIndex)
        return layout.map { card in
            DeckRow(id: stableID(for: card), card: card)
        }
    }

    /// Stable across expand and collapse so the same task card can animate in place.
    private func stableID(for card: StackDeckLayout.Card) -> String {
        switch card.role {
        case .task(let index):
            guard tasks.indices.contains(index) else { return "task-\(index)" }
            return tasks[index].id.uuidString
        case .overflow(let hidden, let first):
            return "overflow-\(first)-\(hidden)"
        }
    }

    private struct DeckRow: Identifiable {
        let id: String
        let card: StackDeckLayout.Card
    }

    private var flipGesture: some Gesture {
        DragGesture(minimumDistance: 28, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                guard vertical > horizontal else { return }
                let direction = StackDeckLayout.flipDirection(
                    translation: Double(value.translation.height),
                    predicted: Double(value.predictedEndTranslation.height)
                )
                guard direction != 0 else { return }
                flip(direction)
            }
    }

    @ViewBuilder
    private func deckSlot(_ card: StackDeckLayout.Card) -> some View {
        switch card.role {
        case .task(let index):
            if tasks.indices.contains(index) {
                taskCard(
                    task: tasks[index],
                    index: index,
                    depth: card.depth,
                    isExpanded: card.isExpanded
                )
            }
        case .overflow(let hidden, let first):
            overflowCard(hiddenCount: hidden, firstHiddenIndex: first, depth: card.depth)
        }
    }

    private func taskCard(
        task: QueueTask,
        index: Int,
        depth: Int,
        isExpanded: Bool
    ) -> some View {
        let live = index == 0 ? focusSnapshot : nil
        // A collapsed Now card has one VoiceOver element, so its label has to track the clock.
        if !isExpanded, let live {
            return AnyView(
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    styledTaskCard(
                        task: task,
                        index: index,
                        depth: depth,
                        isExpanded: false,
                        live: live,
                        label: accessibilityLabel(for: task, index: index, at: context.date, includeRemaining: true)
                    )
                }
            )
        }
        return AnyView(
            styledTaskCard(
                task: task,
                index: index,
                depth: depth,
                isExpanded: isExpanded,
                live: live,
                label: accessibilityLabel(for: task, index: index, at: Date(), includeRemaining: false)
            )
        )
    }

    private func styledTaskCard(
        task: QueueTask,
        index: Int,
        depth: Int,
        isExpanded: Bool,
        live: FocusWidgetSnapshot?,
        label: String
    ) -> some View {
        let cardMenu = menu(index, task)
        return Group {
            if isExpanded {
                expandedCard(task: task, index: index, live: live, onBodyTap: {
                    handleTap(index: index, isExpanded: true)
                })
                .transition(.opacity)
            } else {
                peekFace(task: task, index: index, live: live)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleTap(index: index, isExpanded: false)
                    }
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(
            StackCardChrome(
                depth: depth,
                isNowCard: index == 0,
                focusIsRunning: focusIsRunning,
                isDark: colorScheme == .dark,
                increaseContrast: contrast == .increased
            )
        )
        .modifier(QueueBlockInteractions(menu: cardMenu))
        .modifier(StackCardAccessibility(
            label: label,
            isExpanded: isExpanded,
            isNow: index == 0,
            offersExpand: !isExpanded,
            offersCollapse: isExpanded && index != 0,
            onExpand: { expand(index) },
            onCollapse: collapse,
            onOpenFocus: index == 0 ? { onOpenFocus(task) } : nil,
            menu: cardMenu
        ))
    }

    @ViewBuilder
    private func expandedCard(
        task: QueueTask,
        index: Int,
        live: FocusWidgetSnapshot?,
        onBodyTap: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: QueueSpacing.md) {
            header(task: task, index: index, live: live)
                .contentShape(Rectangle())
                .onTapGesture(perform: onBodyTap)

            Spacer(minLength: 0)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: onBodyTap)
                .accessibilityHidden(true)

            if index == 0 {
                nowControls(task: task, live: live)
            } else if let notes = task.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(QueueColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if index != 0 {
                Button("Edit task") { onEdit(task) }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(QueueColors.primary)
                    .accessibilityHint("Opens the editor for this task")
            }
        }
        .padding(.horizontal, QueueSpacing.lg)
        .padding(.top, QueueSpacing.lg)
        .padding(.bottom, QueueSpacing.lg)
        .frame(
            maxWidth: .infinity,
            minHeight: index == 0 ? 300 : 180,
            alignment: .topLeading
        )
    }

    @ViewBuilder
    private func header(task: QueueTask, index: Int, live: FocusWidgetSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: QueueSpacing.sm) {
            if index == 0 {
                Text("NOW")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(QueueColors.textSecondary)
                    .tracking(1.2)
                    .accessibilityHidden(true)
            }

            HStack(alignment: .top, spacing: QueueSpacing.sm) {
                VStack(alignment: .leading, spacing: QueueSpacing.xs) {
                    Text(task.title)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(QueueColors.textPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .accessibilityLabel(
                            accessibilityLabel(for: task, index: index, at: Date(), includeRemaining: false)
                        )
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityHint(
                            index == 0
                                ? "Opens the full focus screen"
                                : "Collapses the stack"
                        )
                        .queueAccessibilityIdentifier(index == 0 ? QueueAccessibilityID.queueOpenFocus : nil)

                    if live == nil || index != 0 {
                        Text(estimateLine(for: task))
                            .font(.body)
                            .foregroundStyle(QueueColors.textSecondary)
                            .accessibilityHidden(true)
                    }
                }
                Spacer(minLength: QueueSpacing.sm)
                if index == 0, companionVisible {
                    companionBadge(live: live)
                }
            }

            if index == 0, let notes = task.notes, !notes.isEmpty, live == nil {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(QueueColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func nowControls(task: QueueTask, live: FocusWidgetSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: QueueSpacing.sm) {
            if let live {
                StackLiveFocusStatus(
                    snapshot: live,
                    task: task,
                    reduceMotion: reduceMotion || !animationIntensity.allowsMotion,
                    alertsDenied: focusAlertsDenied,
                    onExpire: onExpire
                )
                liveButtons(task: task, state: live.session.state)
            } else {
                Button(startTitle(for: task)) { onStartFocus(task) }
                    .buttonStyle(StackPrimaryButtonStyle())
                    .accessibilityHint("Starts the countdown on this card")
            }

            Button("Edit task") { onEdit(task) }
                .font(.caption.weight(.medium))
                .foregroundStyle(QueueColors.primary)
                .accessibilityHint("Opens the editor for the active task")
        }
    }

    @ViewBuilder
    private func liveButtons(task: QueueTask, state: FocusTimerState) -> some View {
        VStack(spacing: QueueSpacing.sm) {
            HStack(spacing: QueueSpacing.sm) {
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

    private func peekFace(task: QueueTask, index: Int, live: FocusWidgetSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(task.title)
                .font(.headline)
                .foregroundStyle(QueueColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            peekSubtitle(task: task, index: index, live: live)
        }
        .padding(.horizontal, QueueSpacing.lg)
        .padding(.top, QueueSpacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func peekSubtitle(task: QueueTask, index: Int, live: FocusWidgetSnapshot?) -> some View {
        if index == 0, let live {
            TimelineView(.periodic(from: .now, by: reduceMotion ? 1 : 1)) { context in
                Text(livePeekSubtitle(live, at: context.date))
                    .font(.subheadline)
                    .foregroundStyle(QueueColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        } else {
            Text(estimateLine(for: task))
                .font(.subheadline)
                .foregroundStyle(QueueColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func overflowCard(hiddenCount: Int, firstHiddenIndex: Int, depth: Int) -> some View {
        Text(StackDeckLayout.overflowTitle(hiddenCount: hiddenCount))
            .font(.headline)
            .foregroundStyle(QueueColors.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, QueueSpacing.lg)
            .padding(.top, QueueSpacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture {
                expand(firstHiddenIndex)
            }
            .modifier(
                StackCardChrome(
                    depth: depth,
                    isNowCard: false,
                    focusIsRunning: focusIsRunning,
                    isDark: colorScheme == .dark,
                    increaseContrast: contrast == .increased
                )
            )
            .accessibilityLabel(StackDeckLayout.overflowAccessibilityLabel(hiddenCount: hiddenCount))
            .accessibilityHint("Shows the next tasks in the queue")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text("Expand")) { expand(firstHiddenIndex) }
    }

    private func companionBadge(live: FocusWidgetSnapshot?) -> some View {
        CompanionAnimationView(
            state: companionState(live: live),
            reduceMotion: reduceMotion,
            compact: true
        )
        .frame(width: 64, height: 64)
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

    private func startTitle(for task: QueueTask) -> String {
        switch task.status {
        case .active, .paused, .expired:
            return "Continue focus"
        default:
            return "Start focus"
        }
    }

    private func estimateLine(for task: QueueTask) -> String {
        let minutes = max(1, Int(task.estimatedDuration / 60))
        return "\(minutes) min estimate · \(task.difficulty.displayName)"
    }

    private func livePeekSubtitle(_ snapshot: FocusWidgetSnapshot, at date: Date) -> String {
        let clock = FocusTimerFormatting.clock(snapshot.remaining(at: date))
        switch snapshot.session.state {
        case .paused:
            return "Paused · \(clock)"
        case .expired:
            return "Time’s up · \(clock)"
        default:
            return "\(clock) · \(snapshot.difficultyDisplayName)"
        }
    }

    private func accessibilityLabel(
        for task: QueueTask,
        index: Int,
        at date: Date,
        includeRemaining: Bool
    ) -> String {
        var detail = estimateLine(for: task)
        if includeRemaining, let focusSnapshot {
            let spoken = FocusTimerFormatting.spoken(focusSnapshot.remaining(at: date))
            detail += ", \(spoken) remaining"
        }
        return StackDeckLayout.accessibilityLabel(
            position: index + 1,
            total: tasks.count,
            title: task.title,
            detail: detail
        )
    }

    private func handleTap(index: Int, isExpanded: Bool) {
        if isExpanded {
            if index == 0, tasks.indices.contains(0) {
                onOpenFocus(tasks[0])
            } else {
                collapse()
            }
            return
        }
        if index == 0 {
            collapse()
            return
        }
        expand(index)
    }

    private func expand(_ index: Int) {
        withAnimation(deckAnimation) {
            expandedTaskID = StackDeckLayout.taskIDAfterExpand(index: index, ids: ids)
        }
    }

    private func collapse() {
        withAnimation(deckAnimation) {
            expandedTaskID = nil
        }
    }

    private func flip(_ direction: Int) {
        withAnimation(deckAnimation) {
            expandedTaskID = StackDeckLayout.taskIDAfterFlip(
                from: expandedTaskID,
                ids: ids,
                direction: direction
            )
        }
    }
}

/// Places every card at the expanded card's height and steps the next top by the peek,
/// so a back card's body continues under the card in front of it.
private struct WalletStackLayout: Layout {
    var expandedSlot: CGFloat
    var peekHeight: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(expandedSlot, peekHeight) }
        set {
            expandedSlot = newValue.first
            peekHeight = newValue.second
        }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let width = resolvedWidth(proposal: proposal, subviews: subviews)
        let full = fullCardHeight(width: width, subviews: subviews)
        let height = CGFloat(
            StackDeckLayout.visibleStackHeight(
                visibleCount: subviews.count,
                fullHeight: Double(full),
                peekHeight: Double(max(0, peekHeight))
            )
        )
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let full = fullCardHeight(width: bounds.width, subviews: subviews)
        let childProposal = ProposedViewSize(width: bounds.width, height: full)
        var slot = 0
        for subview in subviews {
            let y = CGFloat(
                StackDeckLayout.cardTopOffset(
                    slot: slot,
                    expandedSlot: Double(expandedSlot),
                    fullHeight: Double(full),
                    peekHeight: Double(max(0, peekHeight))
                )
            )
            subview.place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + y),
                anchor: .topLeading,
                proposal: childProposal
            )
            slot += 1
        }
    }

    private func resolvedWidth(proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        if let width = proposal.width, width.isFinite, width > 0 {
            return width
        }
        let fallback = subviews.first?.sizeThatFits(.unspecified).width ?? 0
        return fallback.isFinite ? max(0, fallback) : 0
    }

    /// Ideal height of the tallest card. A nil height proposal asks for that ideal,
    /// so a peek's flexible frame does not inflate the measurement, and a Spacer in
    /// the expanded card does not grow the stack on the next pass.
    private func fullCardHeight(width: CGFloat, subviews: Subviews) -> CGFloat {
        guard width > 1, !subviews.isEmpty else { return max(peekHeight, 1) }
        let proposal = ProposedViewSize(width: width, height: nil)
        var tallest: CGFloat = 0
        for subview in subviews {
            let height = subview.sizeThatFits(proposal).height
            if height.isFinite, height > 0, height < 8_000 {
                tallest = max(tallest, height)
            }
        }
        if tallest > 1 { return tallest }
        return max(peekHeight + 32, 180)
    }
}

// MARK: - Live status

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
            VStack(alignment: .leading, spacing: QueueSpacing.sm) {
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
                            .font(.system(.title, design: .rounded).weight(.medium).monospacedDigit())
                            .foregroundStyle(QueueColors.textPrimary)
                            .contentTransition(.numericText())
                            .accessibilityLabel(
                                "Time remaining \(FocusTimerFormatting.spoken(remaining))"
                            )

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
        switch snapshot.session.state {
        case .paused:
            return "Paused · \(snapshot.difficultyDisplayName)"
        case .expired:
            return "Time’s up · finish when you’re ready"
        case .running:
            return "Focusing · \(snapshot.difficultyDisplayName) · \(max(1, Int(task.estimatedDuration / 60))) min estimate"
        default:
            return "\(max(1, Int(task.estimatedDuration / 60))) min estimate · \(task.difficulty.displayName)"
        }
    }
}

// MARK: - Chrome

private struct StackCardChrome: ViewModifier {
    let depth: Int
    let isNowCard: Bool
    let focusIsRunning: Bool
    let isDark: Bool
    let increaseContrast: Bool
    @Environment(\.queueTheme) private var queueTheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: QueueSpacing.cornerSoft, style: .continuous)
        let scale = CGFloat(StackDeckLayout.depthScale(depth: depth))
        let lighten = StackDeckLayout.depthLightenAmount(depth: depth)
        let opacity = StackDeckLayout.cardOpacity(
            isNowCard: isNowCard,
            focusIsRunning: focusIsRunning,
            increaseContrast: increaseContrast
        )
        content
            .background {
                ZStack {
                    Rectangle().fill(QueueColors.surface)
                    if lighten > 0 {
                        Rectangle().fill(lighterTint.opacity(lighten))
                    }
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    QueueColors.textSecondary.opacity(increaseContrast ? 0.95 : 0.38),
                    lineWidth: increaseContrast ? 1.5 : 1
                )
            }
            .shadow(
                color: StackDeckLayout.showsDepthShadow(isDark: isDark)
                    ? palette(.textPrimary).opacity(0.12)
                    : .clear,
                radius: 14,
                x: 0,
                y: 6
            )
            .scaleEffect(scale, anchor: .top)
            .opacity(opacity)
    }

    /// Dark mode lightens with the ivory text role. Light mode lightens with the background role.
    private var lighterTint: Color {
        palette(isDark ? .textPrimary : .background)
    }

    private func palette(_ role: QueueColorRole) -> Color {
        QueueColors.concrete(
            role,
            theme: queueTheme,
            scheme: isDark ? .dark : .light,
            increasedContrast: increaseContrast
        )
    }
}

private struct StackCardAccessibility: ViewModifier {
    let label: String
    let isExpanded: Bool
    let isNow: Bool
    let offersExpand: Bool
    let offersCollapse: Bool
    var onExpand: () -> Void
    var onCollapse: () -> Void
    var onOpenFocus: (() -> Void)?
    let menu: QueueBlockMenu

    func body(content: Content) -> some View {
        actions(on: spokenCard(content))
    }

    @ViewBuilder
    private func spokenCard(_ content: Content) -> some View {
        if isExpanded {
            // Title and focus controls stay separate VoiceOver elements, in queue order.
            content.accessibilityElement(children: .contain)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(hint)
                .accessibilityAction(.default) { onExpand() }
        }
    }

    private func actions<V: View>(on view: V) -> some View {
        view
            .modifier(NamedAccessibilityAction(enabled: offersExpand, name: "Expand", action: onExpand))
            .modifier(NamedAccessibilityAction(enabled: offersCollapse, name: "Collapse", action: onCollapse))
            .modifier(NamedAccessibilityAction(enabled: onOpenFocus != nil, name: "Open focus") {
                onOpenFocus?()
            })
            .accessibilityAction(named: Text("Edit")) { menu.onEdit() }
            .accessibilityAction(named: Text("Skip")) { menu.onSkip() }
            .accessibilityAction(named: Text("Delete")) { menu.onDelete() }
            .modifier(MoveToBottomAccessibilityAction(enabled: menu.onMoveToBottom != nil) {
                menu.onMoveToBottom?()
            })
    }

    private var hint: String {
        if isExpanded && isNow {
            return "Starts focus from the button. Double tap the title to open the full focus screen."
        }
        if isExpanded {
            return "Double tap the title to collapse the stack."
        }
        return "Expands this task."
    }
}

private struct NamedAccessibilityAction: ViewModifier {
    let enabled: Bool
    let name: String
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
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
            .frame(maxWidth: .infinity, minHeight: QueueSpacing.minTouch)
            .background(
                RoundedRectangle(cornerRadius: QueueSpacing.cornerMinimal, style: .continuous)
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
