import SwiftUI
import SwiftData

/// Organization team management: owners, admins, and managers invite members
/// with a shareable link, give them a title and role, and assign them to
/// projects.
struct TeamView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @Query(filter: #Predicate<OrgMember> { $0.deletedAt == nil }, sort: \OrgMember.createdAt)
    private var members: [OrgMember]

    @State private var isShowingInviteSheet = false
    @State private var editingMember: OrgMember?
    @State private var sharingMember: OrgMember?
    @State private var memberToDelete: OrgMember?
    @State private var upgradeContext: UpgradeContext?

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
                            Text("Invite your crew with a shareable link and assign them to projects.")
                        } actions: {
                            if session.can(.manageTeam) {
                                Button { startInvite() } label: {
                                    // Explicit HStack rather than `Label`: in a
                                    // List/ContentUnavailableView context the
                                    // default label style can drop the glyph.
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus")
                                        Text("Invite Member")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    } else {
                        ForEach(teamMembers) { member in
                            if session.can(.manageTeam) {
                                Button {
                                    editingMember = member
                                } label: {
                                    MemberRow(member: member)
                                }
                                .foregroundStyle(.primary)
                                .contextMenu {
                                    if member.status == .invited {
                                        Button {
                                            sharingMember = member
                                        } label: {
                                            Label("Share Invite Link", systemImage: "link")
                                        }
                                    }
                                    Button(role: .destructive) {
                                        memberToDelete = member
                                    } label: {
                                        Label("Remove Member", systemImage: "person.badge.minus")
                                    }
                                }
                            } else {
                                MemberRow(member: member)
                            }
                        }
                        .onDelete(perform: deleteMembers)
                        .deleteDisabled(!session.can(.manageTeam))
                    }
                } header: {
                    if !teamMembers.isEmpty {
                        Text("Members")
                    }
                } 
            }
            .navigationTitle("Team")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if session.can(.manageTeam) {
                        Button {
                            startInvite()
                        } label: {
                            Image(systemName: "person.badge.plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingInviteSheet) {
                MemberEditorSheet(member: nil)
            }
            .sheet(item: $editingMember) { member in
                MemberEditorSheet(member: member)
            }
            .sheet(item: $sharingMember) { member in
                InviteShareSheet(member: member)
            }
            .sheet(item: $upgradeContext) { context in
                UpgradePromptSheet(context: context)
            }
            .alert(
                "Remove Member",
                isPresented: Binding(get: { memberToDelete != nil }, set: { if !$0 { memberToDelete = nil } }),
                presenting: memberToDelete
            ) { member in
                Button("Remove", role: .destructive) { removeMember(member) }
                Button("Cancel", role: .cancel) { memberToDelete = nil }
            } message: { member in
                Text("Remove \(member.name) from the organization? They will lose access immediately.")
            }
        }
    }

    private func startInvite() {
        if session.activeOrganization?.canAddMember ?? true {
            isShowingInviteSheet = true
        } else {
            upgradeContext = .memberLimit
        }
    }

    private func deleteMembers(at offsets: IndexSet) {
        let store = MemberStore(context: modelContext)
        for offset in offsets {
            store.softDelete(teamMembers[offset])
        }
    }

    private func removeMember(_ member: OrgMember) {
        MemberStore(context: modelContext).softDelete(member)
        memberToDelete = nil
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
                        Text(PhoneNumbers.displayFormatted(member.phoneNumber))
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
        LabelChip(name: member.role.displayName, colorHex: member.role.chipColorHex)
        if member.role != .owner {
            switch member.status {
            case .active:
                LabelChip(name: String(localized: "Active"), colorHex: "#2E933C")
            case .invited:
                LabelChip(name: String(localized: "Invited"), colorHex: "#F7B32B")
            }
        }
    }
}

/// Invite a new member or edit an existing one: name, phone, title, projects.
/// A new invite swaps the sheet's content to `InviteShareSheet` so the link
/// can be shared right away without a dismiss/present race.
struct MemberEditorSheet: View {
    let member: OrgMember?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session
    @Environment(AppServices.self) private var services

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.name)
    private var allProjects: [Project]

    @State private var name = ""
    @State private var phoneNumber = ""
    @State private var title = ""
    @State private var role: OrgMember.Role = .standard
    @State private var selectedProjectIDs: Set<UUID> = []
    @State private var isConfirmingDelete = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    /// Set after a new invite is saved; switches the sheet to link sharing.
    @State private var invitedMember: OrgMember?

    /// Projects in the active organization, the only ones a member can be scoped to.
    private var projects: [Project] {
        allProjects.filter { $0.organization?.id == session.activeOrganizationID }
    }

    private var isOwner: Bool { member?.role == .owner }

    /// Standard members are scoped to the projects they're assigned to, so a
    /// project assignment is required before they can be invited or saved.
    private var needsProjectAssignment: Bool {
        role == .standard && selectedProjectIDs.isEmpty
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && PhoneNumbers.isAcceptable(phoneNumber)
            && !needsProjectAssignment
    }

    var body: some View {
        if let invitedMember {
            InviteShareSheet(member: invitedMember)
        } else {
            editorForm
        }
    }

    private var editorForm: some View {
        NavigationStack {
            Form {
                Section("Member") {
                    TextField("Full name", text: $name)
                        .textContentType(.name)
                    PhoneNumberField("Phone number (optional)", text: $phoneNumber)
                    TextField("Title (e.g. Site Foreman)", text: $title)
                        .textContentType(.jobTitle)
                }

                if !isOwner {
                    Section {
                        if session.can(.changeRoles) {
                            Picker("Role", selection: $role) {
                                ForEach(OrgMember.Role.assignable, id: \.self) { role in
                                    Text(role.displayName).tag(role)
                                }
                            }
                        } else {
                            LabeledContent("Role", value: role.displayName)
                        }
                    } header: {
                        Text("Role")
                    } footer: {
                        if session.can(.changeRoles) {
                            Text(role.summary)
                        } else {
                            Text("Only owners and admins can change roles.")
                        }
                    }

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
                                .foregroundStyle(.primary)
                            }
                        }
                    } header: {
                        Text("Projects")
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            if needsProjectAssignment && !projects.isEmpty {
                                Text("Select at least one project — standard members work only in assigned projects.")
                                    .foregroundStyle(.red)
                            }
                            Text("Standard members can only see assigned projects. Assignments also drive tasks and notifications.")
                        }
                    }
                }

                if let member, member.role != .owner, session.can(.manageTeam) {
                    Section {
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("Remove from Organization")
                                Spacer()
                            }
                        }
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
                    if isWorking {
                        ProgressView()
                    } else {
                        Button(member == nil ? "Invite" : "Save") { save() }
                            .disabled(!canSave)
                    }
                }
            }
            .onAppear(perform: loadExisting)
            .alert(
                "Couldn't invite member",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Remove Member", isPresented: $isConfirmingDelete) {
                Button("Remove", role: .destructive) {
                    if let member {
                        MemberStore(context: modelContext).softDelete(member)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let member {
                    Text("Remove \(member.name) from the organization? They will lose access immediately.")
                }
            }
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
        role = member.role
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
        guard !isWorking else { return }
        let store = MemberStore(context: modelContext)
        let selectedProjects = projects.filter { selectedProjectIDs.contains($0.id) }

        if let member {
            // Member edits stay local and are pushed by Phase 2's sync engine.
            member.name = name.trimmingCharacters(in: .whitespaces)
            member.phoneNumber = phoneNumber.trimmingCharacters(in: .whitespaces)
            member.title = title.trimmingCharacters(in: .whitespaces)
            if member.role != .owner {
                member.projects = selectedProjects
                if session.can(.changeRoles) {
                    store.setRole(role, for: member)
                }
            }
            store.touch(member)
            dismiss()
        } else {
            // New invites are created on the backend so the invite link the next
            // step issues resolves against a real server-side member row.
            guard let organization = session.activeOrganization else { return }
            let inviteRole: OrgMember.Role = session.can(.changeRoles) ? role : .standard
            isWorking = true
            Task {
                defer { isWorking = false }
                do {
                    let created = try await services.memberService.create(
                        in: organization,
                        name: name.trimmingCharacters(in: .whitespaces),
                        phoneNumber: phoneNumber.trimmingCharacters(in: .whitespaces),
                        title: title.trimmingCharacters(in: .whitespaces),
                        role: inviteRole,
                        projects: selectedProjects
                    )
                    // Swap to the share step instead of dismissing.
                    invitedMember = created
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: OrgMember.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let session = Session(context: container.mainContext)
    return TeamView()
        .modelContainer(container)
        .environment(session)
        .environment(AppServices(modelContext: container.mainContext, session: session))
}
