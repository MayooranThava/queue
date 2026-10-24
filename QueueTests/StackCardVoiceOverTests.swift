import Darwin
import SwiftUI
import UIKit
import XCTest
import QueueCore
@testable import Queue

/// Every stack card, front and back, offers the preview and the menu as
/// VoiceOver actions. Delete asks for confirmation and does not remove the task.
@MainActor
final class StackCardVoiceOverTests: XCTestCase {
    func testEveryStackCardExposesPreviewAndMenuActions() {
        let tasks = [
            QueueTestFixture.makeTask(title: "Alpha draft", queuePosition: 0),
            QueueTestFixture.makeTask(title: "Beta outline", queuePosition: 1),
            QueueTestFixture.makeTask(title: "Gamma review", queuePosition: 2)
        ]
        activateAccessibilityRuntime()
        let order = tasks.map(\.id)
        for size in [DynamicTypeSize.large, DynamicTypeSize.accessibility3] {
            let spy = CardSpy()
            let host = DeckHost(tasks: tasks, spy: spy, dynamicTypeSize: size)
            host.install()
            let nodes = waitForCards(in: host, titles: tasks.map(\.title))
            let labels = nodes.map(Self.label(of:))

            for task in tasks {
                let cards = nodes.filter { Self.label(of: $0).contains("Task ") && Self.label(of: $0).contains(task.title) }
                XCTAssertFalse(
                    cards.isEmpty,
                    "No card for \(task.title) at \(size). Labels: \(labels)"
                )
                for card in cards {
                    assertMenuActions(on: card, task: task, spy: spy, tasks: tasks, order: order, size: size)
                }
            }
            host.teardown()
        }
    }

    func testPreviewAcceptsStandardAndIncreasedContrast() {
        let task = QueueTestFixture.makeTask(title: "Contrast sample")
        activateAccessibilityRuntime()
        let content = TaskPreviewContent(task: task, position: 1)
        for contrast in [ColorSchemeContrast.standard, .increased] {
            let preview = TaskPreviewView(
                content: content,
                width: 320,
                onOpen: {},
                onAddDetails: {},
                contrast: contrast
            )
            let host = UIHostingController(rootView: preview)
            let window = Self.makeWindow()
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = Self.windowFrame
            window.layoutIfNeeded()
            let labels = waitForLabels(in: host.view, containing: task.title)
            XCTAssertTrue(
                labels.contains { $0.contains(task.title) },
                "Preview at \(contrast) did not show the title. Labels: \(labels)"
            )
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    private func assertMenuActions(
        on card: NSObject,
        task: QueueTask,
        spy: CardSpy,
        tasks: [QueueTask],
        order: [UUID],
        size: DynamicTypeSize
    ) {
        let names = Set((card.accessibilityCustomActions ?? []).map(\.name))
        for required in Self.menuActionNames {
            XCTAssertTrue(
                names.contains(required),
                "\(task.title) at \(size) missing \(required). Had \(names.sorted())"
            )
        }

        perform("Preview", on: card, expecting: .preview, task: task, spy: spy)
        perform("Start focus", on: card, expecting: .startFocus, task: task, spy: spy)
        perform("Edit", on: card, expecting: .edit, task: task, spy: spy)
        perform("Skip for today", on: card, expecting: .skip, task: task, spy: spy)
        let beforeDelete = spy.events.count
        perform("Delete", on: card, expecting: .deleteConfirmation, task: task, spy: spy)
        let deleteEvents = spy.events.dropFirst(beforeDelete)
        XCTAssertEqual(deleteEvents.map(\.kind), [.deleteConfirmation])
        XCTAssertEqual(tasks.map(\.id), order, "Delete must ask before the task leaves the queue")
    }

    private func perform(
        _ name: String,
        on card: NSObject,
        expecting kind: CardSpy.Kind,
        task: QueueTask,
        spy: CardSpy
    ) {
        let count = spy.events.count
        guard let action = card.accessibilityCustomActions?.first(where: { $0.name == name }) else {
            XCTFail("Missing VoiceOver action \(name) on \(task.title)")
            return
        }
        let handled = action.actionHandler?(action) ?? false
        XCTAssertTrue(handled, "\(name) on \(task.title) did not run")
        XCTAssertEqual(spy.events.count, count + 1, "\(name) on \(task.title) should hit one callback")
        XCTAssertEqual(spy.events.last?.kind, kind)
        XCTAssertEqual(spy.events.last?.id, task.id)
    }

    /// SwiftUI builds VoiceOver elements only while an accessibility client is
    /// attached. Unit tests have none, so turn on the same switch UI tests use.
    private func activateAccessibilityRuntime() {
        guard !Self.accessibilityRuntimeReady else { return }
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(handle, "_AXSSetAutomationEnabled") else {
            XCTFail("The accessibility runtime did not start, so VoiceOver actions cannot be read")
            return
        }
        typealias SetAutomationEnabled = @convention(c) (Bool) -> Void
        unsafeBitCast(symbol, to: SetAutomationEnabled.self)(true)
        Self.accessibilityRuntimeReady = true
    }

    private func waitForCards(in host: DeckHost, titles: [String]) -> [NSObject] {
        let deadline = Date().addingTimeInterval(8)
        var latest: [NSObject] = []
        while Date() < deadline {
            host.layout()
            latest = host.nodes()
            let labels = latest.map(Self.label(of:))
            let ready = titles.allSatisfy { title in
                labels.contains { $0.contains("Task ") && $0.contains(title) }
            }
            if ready { return latest }
            pump()
        }
        return latest
    }

    private func waitForLabels(in view: UIView, containing title: String) -> [String] {
        let deadline = Date().addingTimeInterval(8)
        var labels: [String] = []
        while Date() < deadline {
            view.frame = Self.windowFrame
            view.setNeedsLayout()
            view.layoutIfNeeded()
            _ = view.drawHierarchy(in: Self.windowFrame, afterScreenUpdates: true)
            labels = AccessibilityTree.nodes(in: view).map(Self.label(of:))
            if labels.contains(where: { $0.contains(title) }) {
                return labels
            }
            pump()
        }
        return labels
    }

    private func pump() {
        let published = expectation(description: "accessibility tree")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            published.fulfill()
        }
        wait(for: [published], timeout: 1)
    }

    private static let menuActionNames = ["Preview", "Start focus", "Edit", "Skip for today", "Delete"]
    private static let windowFrame = CGRect(x: 0, y: 0, width: 390, height: 900)
    private static var accessibilityRuntimeReady = false

    private static func label(of element: NSObject) -> String {
        if let label = element.accessibilityLabel, !label.isEmpty {
            return label
        }
        return element.accessibilityAttributedLabel?.string ?? ""
    }

    fileprivate static func makeWindow() -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: windowFrame)
        window.frame = windowFrame
        return window
    }
}

@MainActor
private final class DeckHost {
    private let window: UIWindow
    private let controller: UIHostingController<AnyView>

    init(tasks: [QueueTask], spy: CardSpy, dynamicTypeSize: DynamicTypeSize) {
        let deck = QueueStackDeckView(
            tasks: tasks,
            focusSnapshot: nil,
            focusAlertsDenied: false,
            onEdit: { spy.record(.edit, $0.id) },
            onOpenFocus: { _ in },
            onOpenList: {},
            onStartFocus: { spy.record(.startFocus, $0.id) },
            onPause: { _ in },
            onResume: { _ in },
            onExtend: { _ in },
            onComplete: { _ in },
            onExpire: {},
            onOpenTask: { spy.record(.preview, $0.id) },
            menu: { index, task in
                QueueBlockMenu(
                    onEdit: { spy.record(.edit, task.id) },
                    onMoveUp: index > 0 ? {} : nil,
                    onMoveDown: index < tasks.count - 1 ? {} : nil,
                    onMoveToBottom: index < tasks.count - 1 ? {} : nil,
                    onSkip: { spy.record(.skip, task.id) },
                    onDelete: { spy.record(.deleteConfirmation, task.id) }
                )
            }
        )
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .environment(\.queueCompanionVisible, false)
        .frame(width: 390, height: 900, alignment: .top)

        controller = UIHostingController(rootView: AnyView(deck))
        window = StackCardVoiceOverTests.makeWindow()
    }

    func install() {
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = StackCardVoiceOverTests.windowFrame
        layout()
    }

    func layout() {
        controller.view.frame = StackCardVoiceOverTests.windowFrame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        window.layoutIfNeeded()
        _ = controller.view.drawHierarchy(
            in: StackCardVoiceOverTests.windowFrame,
            afterScreenUpdates: true
        )
    }

    func nodes() -> [NSObject] {
        AccessibilityTree.nodes(in: controller.view)
    }

    func teardown() {
        window.isHidden = true
        window.rootViewController = nil
    }
}

private final class CardSpy {
    enum Kind: Equatable {
        case preview
        case startFocus
        case edit
        case skip
        case deleteConfirmation
    }

    private(set) var events: [(kind: Kind, id: UUID)] = []

    func record(_ kind: Kind, _ id: UUID) {
        events.append((kind, id))
    }
}

private enum AccessibilityTree {
    static func nodes(in root: UIView) -> [NSObject] {
        var collected: [NSObject] = []
        var seen = Set<ObjectIdentifier>()

        func visit(_ object: NSObject) {
            let identity = ObjectIdentifier(object)
            guard seen.insert(identity).inserted else { return }

            let label = object.accessibilityLabel ?? object.accessibilityAttributedLabel?.string ?? ""
            let actions = object.accessibilityCustomActions ?? []
            if object.isAccessibilityElement || !label.isEmpty || !actions.isEmpty {
                collected.append(object)
            }

            let count = object.accessibilityElementCount()
            if count > 0 && count < 2_000 {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) as? NSObject {
                        visit(child)
                    }
                }
            }

            if let elements = object.accessibilityElements {
                for element in elements {
                    if let child = element as? NSObject {
                        visit(child)
                    }
                }
            }

            if let view = object as? UIView {
                for subview in view.subviews {
                    visit(subview)
                }
            }
        }

        visit(root)
        return collected
    }
}
