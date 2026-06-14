import SwiftUI
import SwiftData

/// The notification bell's sheet: the current member's persisted notifications,
/// each with per-item read state and swipe-to-delete, plus tap-through to the
/// related task or project. Hosts its own `NavigationStack` so pushes happen
/// inside the sheet.
struct NotificationsView: View {
    let recipientID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<AppNotification> { $0.deletedAt == nil }, sort: \AppNotification.createdAt, order: .reverse)
    private var allNotifications: [AppNotification]

    @State private var path = NavigationPath()

    private var notifications: [AppNotification] {
        allNotifications.filter { $0.recipient?.id == recipientID }
    }

    private var hasUnread: Bool {
        notifications.contains { !$0.isRead }
    }

    var body: some View {
        NavigationStack(path: $path) {
            listContent
                .navigationTitle("Notifications")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Mark all read") { markAllRead() }
                            .disabled(!hasUnread)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .modifier(NotificationDestinations())
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var listContent: some View {
        if notifications.isEmpty {
            ContentUnavailableView {
                Label("You're all caught up", systemImage: "bell.slash")
            } description: {
                Text("Assignments, mentions, and comments that involve you will show up here.")
            }
        } else {
            List(notifications) { note in
                row(note)
            }
            .listStyle(.plain)
        }
    }

    private func row(_ note: AppNotification) -> some View {
        Button {
            open(note)
        } label: {
            content(note)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                NotificationStore(context: modelContext).softDelete(note)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                NotificationStore(context: modelContext).toggleRead(note)
            } label: {
                Label(note.isRead ? "Unread" : "Read",
                      systemImage: note.isRead ? "envelope.badge" : "envelope.open")
            }
            .tint(.blue)
        }
    }

    private func content(_ note: AppNotification) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(note.isRead ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)

            Image(systemName: note.symbol)
                .font(.title3)
                .foregroundStyle(note.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.displayTitle)
                    .font(.subheadline.weight(note.isRead ? .medium : .semibold))
                    .lineLimit(1)
                if !note.displayMessage.isEmpty {
                    Text(note.displayMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(note.createdAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let actor = note.actor {
                    MemberAvatar(member: actor, size: 24)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func open(_ note: AppNotification) {
        NotificationStore(context: modelContext).markRead(note)
        if let task = note.task {
            path.append(task)
        } else if let photo = note.photo {
            path.append(photo)
        } else if let project = note.project {
            path.append(project)
        }
    }

    private func markAllRead() {
        NotificationStore(context: modelContext).markAllRead(notifications)
    }
}

/// Tap-through destinations for the notification list. Kept in its own modifier
/// so the chain type-checks in a minimal scope (three `navigationDestination`s
/// inline in the view body trips the SwiftUI type-checker).
private struct NotificationDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: ProjectTask.self) { task in
                TaskDetailView(task: task)
            }
            .navigationDestination(for: Project.self) { project in
                ProjectDetailView(project: project)
            }
            .navigationDestination(for: Photo.self) { photo in
                PhotoViewerView(photos: [photo], initialIndex: 0)
            }
    }
}
