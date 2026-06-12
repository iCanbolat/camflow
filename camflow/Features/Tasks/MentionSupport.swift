import SwiftUI

/// Shared mention helpers: composing (@-trigger suggestions) and rendering
/// (highlighting "@Full Name" tokens in comment text).
enum MentionSupport {
    /// The partial name being typed after the last "@", if the user is
    /// currently writing a mention (e.g. "see @Meh" → "Meh").
    static func activeQuery(in text: String) -> String? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        let query = String(text[text.index(after: atIndex)...])
        guard query.count <= 24, !query.contains("\n") else { return nil }
        return query
    }

    static func suggestions(for query: String, members: [OrgMember]) -> [OrgMember] {
        guard !members.isEmpty else { return [] }
        if query.isEmpty { return members }
        return members.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// Replaces the trailing "@partial" with the member's full mention token.
    static func insertMention(of member: OrgMember, into text: String) -> String {
        guard let atIndex = text.lastIndex(of: "@") else { return text }
        return String(text[..<atIndex]) + "@\(member.name) "
    }

    /// Highlights every "@Name" occurrence for the given members.
    static func attributedText(_ text: String, mentionedMembers: [OrgMember]) -> AttributedString {
        var result = AttributedString(text)
        for member in mentionedMembers {
            let token = "@\(member.name)"
            var searchStart = result.startIndex
            while let range = result[searchStart...].range(of: token) {
                result[range].foregroundColor = .accentColor
                result[range].font = .callout.weight(.semibold)
                searchStart = range.upperBound
            }
        }
        return result
    }

    /// IDs of members whose mention token still exists in the final text.
    static func mentionIDs(in text: String, candidates: [OrgMember]) -> [UUID] {
        candidates
            .filter { text.contains("@\($0.name)") }
            .map(\.id)
    }
}

/// Comment composer with @mention autocomplete: typing "@" surfaces member
/// suggestions; picking one inserts the highlighted token.
struct MentionComposer: View {
    @Binding var text: String
    let members: [OrgMember]
    let onSend: () -> Void

    private var suggestions: [OrgMember] {
        guard let query = MentionSupport.activeQuery(in: text) else { return [] }
        return MentionSupport.suggestions(for: query, members: members)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions) { member in
                            Button {
                                text = MentionSupport.insertMention(of: member, into: text)
                            } label: {
                                HStack(spacing: 6) {
                                    MemberAvatar(member: member, size: 22)
                                    Text(member.name)
                                        .font(.callout)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.fill.tertiary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                Divider()
            }

            HStack(spacing: 10) {
                TextField("Add a comment — @ to mention", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)

                Button {
                    onSend()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }
}
