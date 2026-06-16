import SwiftUI
import SwiftData

/// Comment thread for a single photo/video, independent of any task. Mirrors the
/// task comment thread (`TaskDetailView`): a list of comments with @mention
/// highlighting plus a `MentionComposer` pinned to the bottom. Author and
/// mention candidates come from the active organization, so it works for
/// unassigned media too.
struct PhotoCommentsSheet: View {
    let photo: Photo

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session

    @State private var commentText = ""
    @State private var upgradeContext: UpgradeContext?

    private var mentionCandidates: [OrgMember] {
        session.activeOrganization?.activeMembers ?? []
    }

    /// The signed-in user's member row in the active org, falling back to the
    /// org owner (matches `TaskDetailView.sendComment`).
    private var author: OrgMember? {
        session.activeMembership
            ?? session.activeOrganization?.activeMembers.first { $0.role == .owner }
    }

    var body: some View {
        NavigationStack {
            Group {
                if photo.activeComments.isEmpty {
                    ContentUnavailableView {
                        Label("No comments yet", systemImage: "bubble.left")
                    } description: {
                        Text("Add the first comment. Use @ to mention a teammate.")
                    }
                } else {
                    List(photo.activeComments) { comment in
                        PhotoCommentRow(comment: comment, members: mentionCandidates)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Reading existing comments stays open to everyone; only adding new
                // comments is a Pro feature (downgrade rule).
                if session.activePlan.includesComments {
                    MentionComposer(text: $commentText, members: mentionCandidates) {
                        sendComment()
                    }
                } else {
                    lockedCommentBar
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $upgradeContext) { UpgradePromptSheet(context: $0) }
    }

    private var lockedCommentBar: some View {
        Button {
            upgradeContext = .comments
        } label: {
            HStack(spacing: 8) {
                LockBadge()
                Text("Upgrade to Pro to comment")
                    .font(.subheadline)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .buttonStyle(.plain)
    }

    private func sendComment() {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let author else { return }
        let mentionIDs = MentionSupport.mentionIDs(in: text, candidates: mentionCandidates)
        PhotoStore(context: modelContext).addComment(
            to: photo,
            text: text,
            mentionIDs: mentionIDs,
            author: author
        )
        commentText = ""
    }
}

/// One comment row — mirrors `CommentRow` but typed to `PhotoComment`.
struct PhotoCommentRow: View {
    let comment: PhotoComment
    let members: [OrgMember]

    private var mentionedMembers: [OrgMember] {
        members.filter { comment.mentionIDs.contains($0.id) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let author = comment.author {
                MemberAvatar(member: author, size: 30)
            } else {
                Circle()
                    .fill(.fill.secondary)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.author?.name ?? String(localized: "Unknown"))
                        .font(.caption.weight(.semibold))
                    Text(comment.createdAt, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(MentionSupport.attributedText(comment.text, mentionedMembers: mentionedMembers))
                    .font(.callout)
            }
        }
        .padding(.vertical, 2)
    }
}
