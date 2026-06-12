import SwiftUI
import SwiftData

/// Organization team management: the owner invites members by phone number,
/// gives them a title, and scopes them to projects.
struct TeamView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @Query(filter: #Predicate<OrgMember> { $0.deletedAt == nil }, sort: \OrgMember.createdAt)
    private var members: [OrgMember]

    @State private var isShowingInviteSheet = false
    @State private var editingMember: OrgMember?

    /// Members of the active organization.
    private var orgMembers: [OrgMember] {
        members.filter { $0.organization?.id == session.activeOrganizationID }
    }

    private var owner: OrgMember? {
        orgMembers.first { $0.role == .owner }
    }

    private var teamMembers: [OrgMember] {
        orgMembers.filter { $0.role != .owner }
    }

    var body: some View {
        NavigationStack {
            List {
                if let owner {
                    Section("Owner") {
                        MemberRow(member: owner)
                    }
                }

                Section {
                    if teamMembers.isEmpty {
                        ContentUnavailableView {
                            Label("No Team Members Yet", systemImage: "person.2")
                        } description: {
                            Text("Invite your crew by phone number and assign them to projects.")
                        } actions: {
                            Button("Invite Member") { isShowingInviteSheet = true }
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        ForEach(teamMembers) { member in
                            Button {
                                editingMember = member
                            } label: {
                                MemberRow(member: member)
                            }
                            .foregroundStyle(.primary)
                        }
                        .onDelete(perform: deleteMembers)
                    }
                } header: {
                    if !teamMembers.isEmpty {
                        Text("Members")
                    }
                } footer: {
                    if !teamMembers.isEmpty {
                        Text("Members see only the projects they're added to. SMS invites and member sign-in arrive with cloud sync.")
                    }
                }
            }
            .navigationTitle("Team")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingInviteSheet = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingInviteSheet) {
                MemberEditorSheet(member: nil)
            }
            .sheet(item: $editingMember) { member in
                MemberEditorSheet(member: member)
            }
        }
    }

    private func deleteMembers(at offsets: IndexSet) {
        let store = MemberStore(context: modelContext)
        for offset in offsets {
            store.softDelete(teamMembers[offset])
        }
    }
}

/// Initials avatar used wherever members appear.
struct MemberAvatar: View {
    let member: OrgMember
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(Color(hex: member.colorHex).gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(member.initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

struct MemberRow: View {
    let member: OrgMember

    var body: some View {
        HStack(spacing: 12) {
            MemberAvatar(member: member)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(.body.weight(.medium))
                    statusChip
                }
                HStack(spacing: 6) {
                    if !member.title.isEmpty {
                        Text(member.title)
                    }
                    if !member.title.isEmpty && !member.phoneNumber.isEmpty {
                        Text(verbatim: "·")
                    }
                    if !member.phoneNumber.isEmpty {
                        Text(member.phoneNumber)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if member.role != .owner {
                    Text("^[\(member.activeProjects.count) project](inflect: true)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusChip: some View {
        switch (member.role, member.status) {
        case (.owner, _):
            LabelChip(name: String(localized: "Owner"), colorHex: "#FF6B35")
        case (_, .active):
            LabelChip(name: String(localized: "Active"), colorHex: "#2E933C")
        case (_, .invited):
            LabelChip(name: String(localized: "Invited"), colorHex: "#F7B32B")
        }
    }
}

/// Invite a new member or edit an existing one: name, phone, title, projects.
struct MemberEditorSheet: View {
    let member: OrgMember?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.name)
    private var allProjects: [Project]

    @State private var name = ""
    @State private var phoneNumber = ""
    @State private var title = ""
    @State private var selectedProjectIDs: Set<UUID> = []

    /// Projects in the active organization, the only ones a member can be scoped to.
    private var projects: [Project] {
        allProjects.filter { $0.organization?.id == session.activeOrganizationID }
    }

    private var isOwner: Bool { member?.role == .owner }

    private var canSave: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if isOwner { return !trimmedName.isEmpty }
        return !trimmedName.isEmpty && !phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Member") {
                    TextField("Full name", text: $name)
                        .textContentType(.name)
                    TextField("Phone number", text: $phoneNumber)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Title (e.g. Site Foreman)", text: $title)
                        .textContentType(.jobTitle)
                }

                if !isOwner {
                    Section {
                        if projects.isEmpty {
                            Text("Create a project first to assign members.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(projects) { project in
                                Button {
                                    toggleProject(project.id)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(project.name)
                                                .foregroundStyle(.primary)
                                            if !project.address.isEmpty {
                                                Text(project.address)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        if selectedProjectIDs.contains(project.id) {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Projects")
                    } footer: {
                        Text("The member can view these projects, add photos, and work on assigned checklists.")
                    }
                }
            }
            .navigationTitle(memberEditorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(member == nil ? "Invite" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private var memberEditorTitle: LocalizedStringKey {
        if isOwner { return "Edit Owner" }
        return member == nil ? "Invite Member" : "Edit Member"
    }

    private func loadExisting() {
        guard let member else { return }
        name = member.name
        phoneNumber = member.phoneNumber
        title = member.title
        selectedProjectIDs = Set(member.activeProjects.map(\.id))
    }

    private func toggleProject(_ id: UUID) {
        if selectedProjectIDs.contains(id) {
            selectedProjectIDs.remove(id)
        } else {
            selectedProjectIDs.insert(id)
        }
    }

    private func save() {
        let store = MemberStore(context: modelContext)
        let selectedProjects = projects.filter { selectedProjectIDs.contains($0.id) }

        if let member {
            member.name = name.trimmingCharacters(in: .whitespaces)
            member.phoneNumber = phoneNumber.trimmingCharacters(in: .whitespaces)
            member.title = title.trimmingCharacters(in: .whitespaces)
            if member.role != .owner {
                member.projects = selectedProjects
            }
            store.touch(member)
        } else {
            store.invite(
                name: name.trimmingCharacters(in: .whitespaces),
                phoneNumber: phoneNumber.trimmingCharacters(in: .whitespaces),
                title: title.trimmingCharacters(in: .whitespaces),
                projects: selectedProjects,
                organization: session.activeOrganization
            )
        }
        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: OrgMember.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return TeamView()
        .modelContainer(container)
        .environment(Session(context: container.mainContext))
}
