import SwiftUI

/// A thin, app-wide status bar shown above the tab UI when the user needs to
/// know about connectivity/sync: offline (changes are queued), actively syncing,
/// or a sync error (tap to retry). Collapses to nothing when idle + online.
struct SyncStatusBanner: View {
    let state: SyncEngine.State
    let isOnline: Bool
    let onRetry: () -> Void

    var body: some View {
        Group {
            if !isOnline {
                bar(Text("Offline — changes will sync when you reconnect."),
                    systemImage: "wifi.slash", tint: .secondary)
            } else {
                switch state {
                case .syncing:
                    bar(Text("Syncing…"), systemImage: nil, tint: .secondary, showsSpinner: true)
                case let .error(message):
                    Button(action: onRetry) {
                        bar(Text(message), systemImage: "exclamationmark.triangle.fill",
                            tint: .orange, trailing: Text("Retry"))
                    }
                    .buttonStyle(.plain)
                case .idle, .offline:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private func bar(
        _ title: Text,
        systemImage: String?,
        tint: Color,
        showsSpinner: Bool = false,
        trailing: Text? = nil
    ) -> some View {
        HStack(spacing: 8) {
            if showsSpinner {
                ProgressView().controlSize(.mini)
            } else if let systemImage {
                Image(systemName: systemImage)
            }
            title
                .lineLimit(1)
            Spacer(minLength: 4)
            if let trailing {
                trailing.fontWeight(.semibold)
            }
        }
        .font(.caption)
        .foregroundStyle(tint == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
