import Foundation

/// The lines a stack-card preview shows for one task.
///
/// Notes are the steps, one non-empty line each. The preview keeps the first
/// three and marks anything further with `overflowMark`. A why is a single
/// line, and only when the notes include one. It is not counted as a step.
/// Skill is the task's category. Queue position is the 1-based place in the
/// order `QueueOrdering` already shows.
public struct TaskPreviewContent: Equatable, Sendable {
    public static let maxVisibleSteps = 3
    public static let whatToDoHeading = "What to do"
    public static let whyItMattersHeading = "Why it matters"
    public static let emptyDetailsMessage = "No details yet"
    public static let addDetailsTitle = "Add details"
    public static let overflowMark = "…"

    public var taskID: UUID
    public var title: String
    public var minutes: Int
    public var difficultyName: String
    public var skillTag: String?
    /// One line: minutes, difficulty, and the skill tag when the task has one.
    public var metaLine: String
    /// First `maxVisibleSteps` steps. Empty when the task has no details.
    public var steps: [String]
    /// Every step, including ones the preview does not show.
    public var allSteps: [String]
    public var showsOverflow: Bool
    /// One line, or nil when the task has no why.
    public var whyItMatters: String?
    public var position: Int
    public var positionLabel: String
    /// True when there is nothing to show for steps or why.
    public var showsEmptyDetails: Bool

    public init(task: QueueTask, position: Int) {
        let parsed = Self.parse(notes: task.notes)
        let place = max(1, position)
        let minutes = max(1, Int(task.estimatedDuration / 60))
        let skill = Self.skillTag(from: task.category)
        self.taskID = task.id
        self.title = task.title
        self.minutes = minutes
        self.difficultyName = task.difficulty.displayName
        self.skillTag = skill
        self.metaLine = Self.metaLine(minutes: minutes, difficulty: task.difficulty.displayName, skill: skill)
        self.allSteps = parsed.steps
        self.steps = Array(parsed.steps.prefix(Self.maxVisibleSteps))
        self.showsOverflow = parsed.steps.count > Self.maxVisibleSteps
        self.whyItMatters = parsed.why
        self.position = place
        self.positionLabel = "#\(place) in your queue"
        self.showsEmptyDetails = parsed.steps.isEmpty && parsed.why == nil
    }

    /// Steps the preview renders, with `overflowMark` after the third when more exist.
    public var whatToDoLines: [String] {
        guard !steps.isEmpty else { return [] }
        var lines = steps
        if showsOverflow {
            lines.append(Self.overflowMark)
        }
        return lines
    }

    private static func metaLine(minutes: Int, difficulty: String, skill: String?) -> String {
        if let skill, !skill.isEmpty {
            return "\(minutes) min · \(difficulty) · \(skill)"
        }
        return "\(minutes) min · \(difficulty)"
    }

    // MARK: - Notes

    private static func parse(notes: String?) -> (steps: [String], why: String?) {
        let lines = normalizedLines(notes)
        var steps: [String] = []
        var why: String?
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if why == nil, let body = whyBody(in: line) {
                if body.isEmpty, index + 1 < lines.count {
                    let next = oneLine(lines[index + 1])
                    if !next.isEmpty {
                        why = next
                    }
                    index += 2
                } else {
                    if !body.isEmpty {
                        why = oneLine(body)
                    }
                    index += 1
                }
                continue
            }
            if why == nil, isWhyHeading(line), index + 1 < lines.count {
                let next = oneLine(lines[index + 1])
                if !next.isEmpty {
                    why = next
                }
                index += 2
                continue
            }
            if whyBody(in: line) == nil, !isWhyHeading(line) {
                let step = stepText(line)
                if !step.isEmpty {
                    steps.append(step)
                }
            }
            index += 1
        }
        return (steps, why)
    }

    private static func skillTag(from category: String?) -> String? {
        let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedLines(_ notes: String?) -> [String] {
        guard let notes else { return [] }
        let unified = notes
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return unified
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func whyBody(in line: String) -> String? {
        let lowered = line.lowercased()
        for prefix in ["why it matters:", "why:"] where lowered.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func isWhyHeading(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered == "why it matters" || lowered == "why"
    }

    private static func oneLine(_ text: String) -> String {
        text.split { $0.isWhitespace }.joined(separator: " ")
    }

    /// Drops a single leading list marker (`-`, `*`, `•`, `1.`, `2)`).
    private static func stepText(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        for bullet in ["- ", "* ", "• ", "– "] where text.hasPrefix(bullet) {
            return text.dropFirst(bullet.count).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var digits = 0
        for character in text {
            if character.isNumber {
                digits += 1
            } else {
                break
            }
        }
        guard digits > 0, text.count > digits + 1 else {
            return text
        }
        let markerIndex = text.index(text.startIndex, offsetBy: digits)
        let marker = text[markerIndex]
        guard marker == "." || marker == ")" else { return text }
        let rest = text[text.index(after: markerIndex)...]
        guard rest.first == " " else { return text }
        return rest.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
