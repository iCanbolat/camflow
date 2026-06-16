import SwiftUI
import SwiftData

/// Task detail: completion, due date, assignee, evidence photos, and the
/// comment thread with @mention support.
struct TaskDetailView: View {
    @Bindable var task: ProjectTask

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @Query(filter: #Predicate<OrgMember> { $0.deletedAt == nil }, sort: \OrgMember.name)
    private var allMembers: [OrgMember]

    @State private var isShowingEditor = false
    @State private var isShowingPhotoPicker = false
    @State private var isConfirmingDelete = false
    @State private var commentText = ""
    @State private var upgradeContext: UpgradeContext?

    /// Acting on the task (complete, comment, attach photos) is open to the
    /// assignee and privileged roles; structural changes (edit/delete) require
    /// `.manageTasks`.
    private var canAct: Bool { session.canModify(task) }
    private var canManage: Bool { session.can(.manageTasks) }

    private var mentionCandidates: [OrgMember] {
        guard let project = task.project else { return allMembers }
        return AssigneePicker.candidates(for: project, context: modelContext)
    }

    private var attachedPhotos: [Photo] {
        guard let project = task.project else { return [] }
        return task.attachedPhotoIDs.compactMap { id in
            project.activePhotos.first { $0.id == id }
        }
    }

    var body: some View {
        List {
            statusSection
            detailsSection

            if !task.note.isEmpty {
                Section("Note") {
                    Text(task.note)
                }
            }

            photosSection
            commentsSection
        }
        .navigationTitle(task.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isShowingEditor = true
                        } label: {
                            Label("Edit Task", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("Delete Task", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if canAct {
                // Existing comments stay readable; adding new ones is a Pro feature.
                if session.activePlan.includesComments {
                    MentionComposer(text: $commentText, members: mentionCandidates) {
                        sendComment()
                    }
                } else {
                    lockedCommentBar
                }
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            if let project = task.project {
                TaskEditorSheet(project: project, task: task)
            }
        }
        .sheet(isPresented: $isShowingPhotoPicker) {
            if let project = task.project {
                ProjectPhotoPickerSheet(project: project, excludedIDs: Set(task.attachedPhotoIDs)) { photos in
                    task.attachedPhotoIDs.append(contentsOf: photos.map(\.id))
                    TaskStore(context: modelContext).touch(task)
                }
            }
        }
        .confirmationDialog("Delete this task?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                TaskStore(context: modelContext).softDelete(task)
                dismiss()
            }
        }
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

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            Button {
                TaskStore(context: modelContext).toggleCompletion(task)
            } label: {
                statusLabel
            }
            .disabled(!canAct)
        }
    }

    private var statusLabel: some View {
                HStack {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.isCompleted ? .green : .secondary)
                    if let completedAt = task.completedAt {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Completed")
                                .foregroundStyle(.primary)
                            Text(completedAt, format: .dateTime.day().month().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Mark Complete")
                            .foregroundStyle(.primary)
                    }
                }
    }

    private var detailsSection: some View {
        Section {
            if let dueDate = task.dueDate {
                LabeledContent("Due") {
                    Text(dueDate, format: .dateTime.weekday().day().month())
                        .foregroundStyle(task.isOverdue ? .red : .secondary)
                }
            }
            HStack {
                Text("Assignee")
                Spacer()
                if let assignee = task.assignee, assignee.deletedAt == nil {
                    MemberAvatar(member: assignee, size: 24)
                    Text(assignee.name)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Unassigned")
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var photosSection: some View {
        if !attachedPhotos.isEmpty || canAct {
            Section("Photos") {
                if !attachedPhotos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(attachedPhotos) { photo in
                                NavigationLink(value: photo) {
                                    PhotoCell(photo: photo)
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if canAct {
                                        Button(role: .destructive) {
                                            task.attachedPhotoIDs.removeAll { $0 == photo.id }
                                            TaskStore(context: modelContext).touch(task)
                                        } label: {
                                            Label("Remove from Task", systemImage: "minus.circle")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                if canAct {
                    Button {
                        isShowingPhotoPicker = true
                    } label: {
                        Label("Attach Photos", systemImage: "photo.badge.plus")
                    }
                }
            }
        }
    }

    private var commentsSection: some View {
        Section("Comments") {
            if task.activeComments.isEmpty {
                Text("No comments yet. Use @ to mention a teammate.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(task.activeComments) { comment in
                    CommentRow(comment: comment, allMembers: allMembers)
                }
            }
        }
    }

    private func sendComment() {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let mentionIDs = MentionSupport.mentionIDs(in: text, candidates: mentionCandidates)
        // Comment author = the signed-in user's member row in this project's org,
        // falling back to the org owner.
        let orgMembers = task.project?.organization?.activeMembers ?? []
        let accountID = session.currentAccount?.id
        guard let author = orgMembers.first(where: { $0.accountID == accountID })
            ?? orgMembers.first(where: { $0.role == .owner }) else { return }
        TaskStore(context: modelContext).addComment(
            to: task,
            text: text,
            mentionIDs: mentionIDs,
            author: author
        )
        commentText = ""
    }
}

struct CommentRow: View {
    let comment: TaskComment
    let allMembers: [OrgMember]

    private var mentionedMembers: [OrgMember] {
        allMembers.filter { comment.mentionIDs.contains($0.id) }
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
