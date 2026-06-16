import SwiftUI
import SwiftData

/// Dedicated storage screen with two tabs:
/// - **Cloud** (Bunny.net): the plan quota — an animated usage ring + purchasable
///   add-ons. Add-on management is owner/admin only (`.manageBilling`).
/// - **This Device**: the app's on-device footprint plus the device's free space,
///   with the option to clear local media to free space (the media stays in the
///   Bunny.net cloud and re-downloads on demand once sync ships).
/// Local-first mock — cloud/add-ons are forward-looking; real billing & sync
/// arrive with cloud accounts.
struct StorageView: View {
    enum Tab: Hashable { case cloud, device }

    /// What a destructive "clear" action targets on the device tab.
    enum ClearTarget: String, Identifiable {
        case photos, reports, pages, all
        var id: String { rawValue }

        var title: String {
            switch self {
            case .photos: String(localized: "Photos & Videos")
            case .reports: String(localized: "Reports")
            case .pages: String(localized: "Pages")
            case .all: String(localized: "All Local Media")
            }
        }

        var directories: [FileStorage.Directory] {
            switch self {
            case .photos: [.photos]
            case .reports: [.reports]
            case .pages: [.pages]
            case .all: [.photos, .reports, .pages]
            }
        }
    }

    @Environment(Session.self) private var session

    @State private var tab: Tab = .cloud
    @State private var ringProgress: Double = 0
    @State private var pendingAddOn: StorageAddOn?
    @State private var pendingClear: ClearTarget?
    /// Bumped after a clear so the size-reading computed properties re-evaluate.
    @State private var refreshToken = 0

    // MARK: - Sizes (recomputed each render; `refreshToken` forces a refresh)

    private var photos: Int64 { FileStorage.totalSize(of: .photos) }
    private var reports: Int64 { FileStorage.totalSize(of: .reports) }
    private var pages: Int64 { FileStorage.totalSize(of: .pages) }
    private var used: Int64 { photos + reports + pages }

    private var total: Int64 { session.activeStorageLimit }
    private var remaining: Int64 { max(total - used, 0) }
    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(Double(used) / Double(total), 1)
    }
    private var isOver: Bool { used >= total }
    private var canManageBilling: Bool { session.can(.manageBilling) }

    /// Device volume capacity/availability, or nil if it can't be read.
    private var deviceCapacity: (total: Int64, free: Int64)? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]) else { return nil }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let free = values.volumeAvailableCapacityForImportantUsage ?? 0
        return (total, free)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Storage location", selection: $tab) {
                Text("Cloud").tag(Tab.cloud)
                Text("This Device").tag(Tab.device)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.vertical, 8)

            if tab == .cloud {
                cloudList
            } else {
                deviceList
                    .id(refreshToken)
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { ringProgress = fraction } }
        .onChange(of: fraction) { _, newValue in
            withAnimation(.easeOut(duration: 0.6)) { ringProgress = newValue }
        }
        .confirmationDialog(
            pendingAddOn.map { String(localized: "Add \($0.displayName) storage?") } ?? "",
            isPresented: Binding(get: { pendingAddOn != nil }, set: { if !$0 { pendingAddOn = nil } }),
            titleVisibility: .visible
        ) {
            Button("Add Storage") {
                if let addOn = pendingAddOn { session.setStorageAddOn(addOn) }
                pendingAddOn = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let addOn = pendingAddOn {
                Text(verbatim: "\(addOn.displayName) · \(addOn.price)/month")
            }
        }
        .confirmationDialog(
            pendingClear.map { String(localized: "Clear \($0.title)?") } ?? "",
            isPresented: Binding(get: { pendingClear != nil }, set: { if !$0 { pendingClear = nil } }),
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                if let target = pendingClear {
                    target.directories.forEach(FileStorage.clear)
                    refreshToken += 1
                }
                pendingClear = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees space on this device. Your media stays in your Bunny.net cloud and re-downloads when you need it.")
        }
    }

    // MARK: - Cloud tab

    private var cloudList: some View {
        List {
            Section {
                ring
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .listRowBackground(Color.clear)
            } footer: {
                Label("Cloud storage powered by Bunny.net", systemImage: "cloud.fill")
                    .frame(maxWidth: .infinity)
            }

            Section("In the Cloud") {
                breakdownRow("Photos & Videos", systemImage: "photo.fill", bytes: photos)
                breakdownRow("Reports", systemImage: "doc.richtext.fill", bytes: reports)
                breakdownRow("Pages", systemImage: "doc.text.fill", bytes: pages)
            }

            Section {
                ForEach(StorageAddOn.purchasable, id: \.self) { addOn in
                    addOnRow(addOn)
                }
                if session.activeStorageAddOn != .none {
                    Button("Remove add-on", role: .destructive) {
                        session.setStorageAddOn(.none)
                    }
                    .disabled(!canManageBilling)
                }
            } header: {
                Text("Add-on Storage")
            } footer: {
                Text(canManageBilling
                     ? "Add-ons stack on top of your \(session.activePlan.displayName) plan's \(session.activePlan.storageDisplay). Billed monthly — instant and free today; real payments arrive with cloud accounts."
                     : "Only owners and admins can change storage add-ons.")
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 18)
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    isOver ? Color.red : Color.accentColor,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text(remaining, format: .byteCount(style: .file))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .foregroundStyle(isOver ? .red : .primary)
                Text("free")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("of \(Text(total, format: .byteCount(style: .file)))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 210, height: 210)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cloud storage"))
        .accessibilityValue(Text("\(Text(used, format: .byteCount(style: .file))) of \(Text(total, format: .byteCount(style: .file))) used"))
    }

    // MARK: - Device tab

    private var deviceList: some View {
        List {
            Section {
                deviceGauge
                    .listRowBackground(Color.clear)
            } footer: {
                Text("How much space CamFlow is using on this device.")
            }

            Section {
                deviceFileRow("Photos & Videos", systemImage: "photo.fill", bytes: photos, target: .photos)
                deviceFileRow("Reports", systemImage: "doc.richtext.fill", bytes: reports, target: .reports)
                deviceFileRow("Pages", systemImage: "doc.text.fill", bytes: pages, target: .pages)
            } header: {
                Text("On-Device Media")
            } footer: {
                Text("Swipe a row to clear that category. Cleared media stays in your Bunny.net cloud and re-downloads when you open it.")
            }

            Section {
                Button("Clear All Local Media", role: .destructive) {
                    pendingClear = .all
                }
                .frame(maxWidth: .infinity)
                .disabled(used == 0)
            }
        }
    }

    private var deviceGauge: some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(used, format: .byteCount(style: .file))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("used by CamFlow on this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let capacity = deviceCapacity {
                let deviceUsed = max(capacity.total - capacity.free, 0)
                VStack(spacing: 6) {
                    ProgressView(
                        value: Double(min(deviceUsed, capacity.total)),
                        total: Double(max(capacity.total, 1))
                    )
                    .tint(.accentColor)
                    HStack {
                        Text("\(Text(capacity.free, format: .byteCount(style: .file))) free")
                        Spacer()
                        Text("\(Text(capacity.total, format: .byteCount(style: .file))) total")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rows

    private func breakdownRow(_ title: LocalizedStringKey, systemImage: String, bytes: Int64) -> some View {
        LabeledContent {
            Text(bytes, format: .byteCount(style: .file))
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func deviceFileRow(_ title: LocalizedStringKey, systemImage: String, bytes: Int64, target: ClearTarget) -> some View {
        LabeledContent {
            Text(bytes, format: .byteCount(style: .file))
        } label: {
            Label(title, systemImage: systemImage)
        }
        .swipeActions(edge: .trailing) {
            if bytes > 0 {
                Button(role: .destructive) {
                    pendingClear = target
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }
        }
    }

    private func addOnRow(_ addOn: StorageAddOn) -> some View {
        let isCurrent = session.activeStorageAddOn == addOn
        return Button {
            if !isCurrent { pendingAddOn = addOn }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(addOn.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(verbatim: "\(addOn.price) / month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                }
            }
        }
        .disabled(isCurrent || !canManageBilling)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Organization.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return NavigationStack { StorageView() }
        .modelContainer(container)
        .environment(Session(context: container.mainContext))
}
