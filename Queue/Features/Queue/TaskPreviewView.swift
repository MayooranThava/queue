import SwiftUI
import QueueCore

/// Lifted preview for a stack card. About as wide as the card, and never taller
/// than 420 points. Text styles follow Dynamic Type.
struct TaskPreviewView: View {
    let content: TaskPreviewContent
    var width: CGFloat
    var onOpen: () -> Void
    var onAddDetails: () -> Void

    @Environment(\.queueTheme) private var queueTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ViewThatFits(in: .vertical) {
            previewColumn
            ScrollView {
                previewColumn
            }
        }
        .frame(width: resolvedWidth, alignment: .topLeading)
        .frame(maxHeight: Self.maxHeight, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(QueueColors.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .environment(\.queueTheme, queueTheme)
        .environment(\.colorScheme, colorScheme)
        .environment(\.colorSchemeContrast, contrast)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: QueueSpacing.sm) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: QueueSpacing.sm) {
                    previewFacts
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the full task")

            if content.showsEmptyDetails {
                addDetailsButton
            }

            Button(action: onOpen) {
                Text(content.positionLabel)
                    .font(.footnote)
                    .foregroundStyle(QueueColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the full task")
        }
        .padding(18)
    }

    /// Title, meta, and the steps or the empty line. Position sits below Add details.
    private var previewFacts: some View {
        VStack(alignment: .leading, spacing: QueueSpacing.sm) {
            Text(content.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(QueueColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(content.metaLine)
                .font(.subheadline)
                .foregroundStyle(QueueColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if content.showsEmptyDetails {
                Text(TaskPreviewContent.emptyDetailsMessage)
                    .font(.body)
                    .foregroundStyle(QueueColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if !content.steps.isEmpty {
                    Text(TaskPreviewContent.whatToDoHeading)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(QueueColors.textPrimary)
                    ForEach(Array(content.steps.enumerated()), id: \.offset) { _, step in
                        Text(step)
                            .font(.body)
                            .foregroundStyle(QueueColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if content.showsOverflow {
                        Text(TaskPreviewContent.overflowMark)
                            .font(.body)
                            .foregroundStyle(QueueColors.textSecondary)
                            .accessibilityLabel("More steps")
                    }
                }
                if let why = content.whyItMatters {
                    Text(TaskPreviewContent.whyItMattersHeading)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(QueueColors.textPrimary)
                    Text(why)
                        .font(.body)
                        .foregroundStyle(QueueColors.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var addDetailsButton: some View {
        Button(action: onAddDetails) {
            Text(TaskPreviewContent.addDetailsTitle)
                .font(.body.weight(.semibold))
                .foregroundStyle(QueueColors.primary)
                .frame(maxWidth: .infinity, minHeight: QueueSpacing.minTouch, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var resolvedWidth: CGFloat {
        width > 1 ? width : Self.fallbackWidth
    }

    static let maxHeight: CGFloat = 420
    static let cornerRadius: CGFloat = 22
    static let fallbackWidth: CGFloat = 320
}

/// The task a preview tap opens. Same facts as the lift, with every step,
/// and the same actions the card already offers.
struct TaskPageView: View {
    let task: QueueTask
    let position: Int
    var onStartFocus: () -> Void
    var onEdit: () -> Void
    var onAddDetails: () -> Void
    var onSkip: () -> Void
    var onDelete: () -> Void
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onMoveToBottom: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.queueTheme) private var queueTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var content: TaskPreviewContent {
        TaskPreviewContent(task: task, position: position)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: QueueSpacing.lg) {
                    TaskPreviewDetails(
                        content: content,
                        showsAllSteps: true,
                        limitWhyToOneLine: false,
                        onAddDetails: content.showsEmptyDetails ? onAddDetails : nil
                    )

                    VStack(spacing: QueueSpacing.sm) {
                        PreviewMenuButton(title: "Start focus", role: .primary, action: onStartFocus)
                        PreviewMenuButton(title: "Edit", role: .secondary, action: onEdit)
                        PreviewMenuButton(title: "Skip for today", role: .secondary, action: onSkip)
                        PreviewMenuButton(title: "Delete", role: .destructive, action: onDelete)
                    }
                }
                .padding(QueueSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background {
                QueueThemeBackground()
            }
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .environment(\.queueTheme, queueTheme)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
        }
        .accessibilityAction(named: Text("Edit")) { onEdit() }
        .accessibilityAction(named: Text("Skip")) { onSkip() }
        .accessibilityAction(named: Text("Delete")) { onDelete() }
        .modifier(MoveToBottomAccessibilityAction(enabled: onMoveToBottom != nil) {
            onMoveToBottom?()
        })
        .modifier(PreviewMoveAction(name: "Move up", action: onMoveUp))
        .modifier(PreviewMoveAction(name: "Move down", action: onMoveDown))
    }
}

/// Title, meta line, steps, why, and queue place. Picks its lines from
/// `TaskPreviewContent` and does not decide which ones exist.
private struct TaskPreviewDetails: View {
    let content: TaskPreviewContent
    var showsAllSteps: Bool
    var limitWhyToOneLine: Bool
    var onAddDetails: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: QueueSpacing.sm) {
            Text(content.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(QueueColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(content.metaLine)
                .font(.subheadline)
                .foregroundStyle(QueueColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if content.showsEmptyDetails {
                Text(TaskPreviewContent.emptyDetailsMessage)
                    .font(.body)
                    .foregroundStyle(QueueColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let onAddDetails {
                    Button(action: onAddDetails) {
                        Text(TaskPreviewContent.addDetailsTitle)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(QueueColors.primary)
                            .frame(maxWidth: .infinity, minHeight: QueueSpacing.minTouch, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            } else if !visibleSteps.isEmpty {
                Text(TaskPreviewContent.whatToDoHeading)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(QueueColors.textPrimary)
                ForEach(Array(visibleSteps.enumerated()), id: \.offset) { _, step in
                    Text(step)
                        .font(.body)
                        .foregroundStyle(QueueColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !showsAllSteps, content.showsOverflow {
                    Text(TaskPreviewContent.overflowMark)
                        .font(.body)
                        .foregroundStyle(QueueColors.textSecondary)
                        .accessibilityLabel("More steps")
                }
            }

            if let why = content.whyItMatters {
                Text(TaskPreviewContent.whyItMattersHeading)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(QueueColors.textPrimary)
                Text(why)
                    .font(.body)
                    .foregroundStyle(QueueColors.textSecondary)
                    .lineLimit(limitWhyToOneLine ? 1 : nil)
                    .fixedSize(horizontal: false, vertical: !limitWhyToOneLine)
            }

            Text(content.positionLabel)
                .font(.footnote)
                .foregroundStyle(QueueColors.textSecondary)
        }
        .accessibilityElement(children: .contain)
    }

    private var visibleSteps: [String] {
        showsAllSteps ? content.allSteps : content.steps
    }
}

/// Long-press menu for one stack card. The lift uses the system context menu,
/// so the haptic and the preview are the ones iOS already provides.
struct StackTaskPreview: ViewModifier {
    let task: QueueTask
    let position: Int
    let menu: QueueBlockMenu
    var onStartFocus: () -> Void
    var onOpen: () -> Void

    @Environment(\.queueTheme) private var queueTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var cardWidth: CGFloat = 0

    func body(content: Content) -> some View {
        let preview = TaskPreviewContent(task: task, position: position)
        content
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: StackCardWidthKey.self, value: proxy.size.width)
                }
            }
            .onPreferenceChange(StackCardWidthKey.self) { newValue in
                guard newValue > 1, abs(newValue - cardWidth) > 0.5 else { return }
                cardWidth = newValue
            }
            .contextMenu(menuItems: {
                Button(action: onStartFocus) {
                    Label("Start focus", systemImage: "timer")
                }
                Button(action: menu.onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(action: menu.onSkip) {
                    Label("Skip for today", systemImage: "forward.end")
                }
                Button(role: .destructive, action: menu.onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }, preview: {
                TaskPreviewView(
                    content: preview,
                    width: cardWidth,
                    onOpen: onOpen,
                    onAddDetails: menu.onEdit
                )
                .environment(\.queueTheme, queueTheme)
                .environment(\.colorScheme, colorScheme)
                .environment(\.colorSchemeContrast, contrast)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
            })
    }
}

private struct PreviewMenuButton: View {
    enum Role {
        case primary
        case secondary
        case destructive
    }

    var title: String
    var role: Role
    var action: () -> Void

    var body: some View {
        Button(role: buttonRole, action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: QueueSpacing.minTouch)
                .background {
                    RoundedRectangle(cornerRadius: QueueSpacing.cornerMinimal, style: .continuous)
                        .fill(fill)
                }
        }
        .buttonStyle(.plain)
    }

    private var buttonRole: ButtonRole? {
        role == .destructive ? ButtonRole.destructive : nil
    }

    private var fill: QueueColorStyle {
        switch role {
        case .primary:
            return QueueColors.primary
        case .secondary:
            return QueueColors.surface
        case .destructive:
            return QueueColors.danger
        }
    }

    private var foreground: QueueColorStyle {
        switch role {
        case .primary, .destructive:
            return QueueColors.onPrimary
        case .secondary:
            return QueueColors.textPrimary
        }
    }
}

private struct PreviewMoveAction: ViewModifier {
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

private struct StackCardWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}
