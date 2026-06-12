import SwiftUI

struct SettingsView: View {
    @AppStorage("quickTagAfterCapture") private var quickTagAfterCapture = false
    @AppStorage("brandedExportDefault") private var brandedExportDefault = true
    @AppStorage("photoQuality") private var photoQuality = "high"

    var body: some View {
        Form {
            Section("Capture") {
                Toggle("Quick-tag after capture", isOn: $quickTagAfterCapture)
                Picker("Photo quality", selection: $photoQuality) {
                    Text("High").tag("high")
                    Text("Medium").tag("medium")
                }
            }

            Section {
                Toggle("Branded exports by default", isOn: $brandedExportDefault)
            } header: {
                Text("Sharing")
            } footer: {
                Text("Branded exports include your company logo and the photo's time and location stamp.")
            }

            Section("Storage") {
                LabeledContent("Photos & Videos") {
                    Text(FileStorage.totalSize(of: .photos), format: .byteCount(style: .file))
                }
                LabeledContent("Reports") {
                    Text(FileStorage.totalSize(of: .reports), format: .byteCount(style: .file))
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
