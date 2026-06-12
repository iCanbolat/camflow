import SwiftUI
import SwiftData

/// Toggles which team members belong to a project.
struct MemberPickerSheet: View {
    @Bindable var project: Project

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<OrgMember> { $0.deletedAt == nil }, sort: \OrgMember.name)
    private var members: [OrgMember]

    private var selectableMembers: [OrgMember] {
        members.filter { $0.role != .owner && $0.organization?.id == project.organization?.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if selectableMembers.isEmpty {
                    ContentUnavailableView {
                        Label("No Team Members", systemImage: "person.2")
                    } description: {
                        Text("Invite members from the Team tab, then add them to this project.")
                    }
                } else {
                    List(selectableMembers) { member in
                        Button {
                            toggle(member)
                        } label: {
                            HStack(spacing: 12) {
                                MemberAvatar(member: member, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name)
                                        .foregroundStyle(.primary)
                                    if !member.title.isEmpty {
                                        Text(member.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if isMember(member) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Project Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func isMember(_ member: OrgMember) -> Bool {
        project.members.contains { $0.id == member.id }
    }

    private func toggle(_ member: OrgMember) {
        let store = MemberStore(context: modelContext)
        if isMember(member) {
            project.members.removeAll { $0.id == member.id }
        } else {
            project.members.append(member)
        }
        store.touch(member)
        ProjectStore(context: modelContext).touch(project)
    }
}
