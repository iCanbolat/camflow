import SwiftUI

struct SettingsView: View {
    @AppStorage("brandedExportDefault") private var brandedExportDefault = true
    @AppStorage("photoQuality") private var photoQuality = "high"

    var body: some View {
        Form {
            Section("Capture") {
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
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
