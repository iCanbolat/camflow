import SwiftUI
import AVFoundation

/// Explains why CamFlow needs camera, microphone + location before the system prompts.
struct PermissionPrimingView: View {
    var onContinue: () -> Void

    @Environment(LocationService.self) private var locationService
    @State private var cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text("Before You Start")
                    .font(.largeTitle.bold())
                Text("CamFlow works best with these permissions enabled.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            VStack(spacing: 16) {
                PermissionCard(
                    systemImage: "camera.fill",
                    title: "Camera",
                    message: "Capture job site photos directly in the app.",
                    isGranted: cameraGranted
                ) {
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        Task { @MainActor in cameraGranted = granted }
                    }
                }

                PermissionCard(
                    systemImage: "microphone.fill",
                    title: "Microphone",
                    message: "Record audio with your job site videos.",
                    isGranted: microphoneGranted
                ) {
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        Task { @MainActor in microphoneGranted = granted }
                    }
                }

                PermissionCard(
                    systemImage: "location.fill",
                    title: "Location",
                    message: "Stamp photos with GPS and suggest the nearest project.",
                    isGranted: locationService.isAuthorized
                ) {
                    locationService.requestAuthorization()
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                onContinue()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

private struct PermissionCard: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else {
                Button("Enable", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
