import SwiftUI

/// Display formatting for the persisted `AppNotification` model (kept out of the
/// model file so the model stays SwiftUI-free). Strings are built at display
/// time from the live relationships, so renames stay current.
extension AppNotification {
    var symbol: String {
        switch kind {
        case .taskAssigned: "person.crop.circle.badge.checkmark"
        case .checklistAssigned: "checklist"
        case .mention: "at"
        case .comment: "bubble.left.fill"
        }
    }

    var color: Color {
        switch kind {
        case .taskAssigned: .blue
        case .checklistAssigned: .indigo
        case .mention: .purple
        case .comment: .teal
        }
    }

    /// Headline line.
    var displayTitle: String {
        switch kind {
        case .taskAssigned:
            task?.title ?? String(localized: "A task")
        case .checklistAssigned:
            checklist?.name ?? String(localized: "A checklist")
        case .mention:
            String(localized: "\(actorName) mentioned you")
        case .comment:
            String(localized: "\(actorName) commented")
        }
    }

    /// Secondary detail line.
    var displayMessage: String {
        switch kind {
        case .taskAssigned:
            joined([String(localized: "Assigned to you"), project?.name])
        case .checklistAssigned:
            joined([String(localized: "Checklist assigned to you"), project?.name])
        case .mention, .comment:
            joined([task?.title, snippet])
        }
    }

    private var actorName: String {
        actor?.name ?? String(localized: "Someone")
    }

    private var snippet: String? {
        let trimmed = bodySnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let clipped = trimmed.count > 80 ? String(trimmed.prefix(80)) + "…" : trimmed
        return "“\(clipped)”"
    }

    private func joined(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.joined(separator: " · ")
    }
}
