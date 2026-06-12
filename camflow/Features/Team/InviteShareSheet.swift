import SwiftUI
import SwiftData
import UIKit

/// Shown right after inviting a member (and via "Share Invite Link" on
/// invited rows): the invite link plus quick share actions. The code is
/// issued lazily and idempotently, so re-opening reuses the same link.
struct InviteShareSheet: View {
    let member: OrgMember

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var link: InviteLink?
    @State private var didCopy = false

    private var organizationName: String {
        member.organization?.name ?? "CamFlow"
    }

    private var shareMessage: String {
        guard let link else { return "" }
        return String(
            localized: "Join \(organizationName) on CamFlow: \(link.universalURL.absoluteString) — invite code \(link.code)"
        )
    }

    private var whatsAppURL: URL? {
        guard link != nil,
              let encoded = shareMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "whatsapp://send?text=\(encoded)"),
              let probe = URL(string: "whatsapp://"),
              UIApplication.shared.canOpenURL(probe) else { return nil }
        return url
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        MemberAvatar(member: member, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name)
                                .font(.body.weight(.medium))
                            Text("Invite to \(organizationName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if let link {
                    Section {
                        VStack(spacing: 6) {
                            Text(link.code)
                                .font(.system(.title, design: .monospaced).weight(.semibold))
                                .kerning(3)
                                .frame(maxWidth: .infinity)
                            Text(link.universalURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 6)
                    } header: {
                        Text("Invite Code")
                    } footer: {
                        Text("The link opens CamFlow when it's installed; otherwise it shows download steps and this code for manual entry.")
                    }

                    Section {
                        Button {
                            UIPasteboard.general.url = link.universalURL
                            didCopy = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                didCopy = false
                            }
                        } label: {
                            Label(
                                didCopy ? String(localized: "Copied!") : String(localized: "Copy Link"),
                                systemImage: didCopy ? "checkmark" : "link"
                            )
                        }

                        if let whatsAppURL {
                            Link(destination: whatsAppURL) {
                                Label("Share via WhatsApp", systemImage: "message")
                            }
                        }

                        ShareLink(item: link.universalURL, message: Text(shareMessage)) {
                            Label("More…", systemImage: "square.and.arrow.up")
                        }
                    }
                } else {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Preparing invite link…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Invite Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                link = try? await LocalInviteService(context: modelContext).issueInvite(for: member)
            }
        }
    }
}
