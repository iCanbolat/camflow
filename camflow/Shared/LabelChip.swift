import SwiftUI

/// Small colored capsule used for project labels and photo tags.
struct LabelChip: View {
    let name: String
    let colorHex: String

    var body: some View {
        Text(name)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: colorHex).opacity(0.18), in: Capsule())
            .foregroundStyle(Color(hex: colorHex))
    }
}

/// Reusable color swatch row for tag/label editors.
struct ColorSwatchPicker: View {
    @Binding var selectedHex: String

    var body: some View {
        HStack(spacing: 12) {
            ForEach(TagPalette.colors, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 32, height: 32)
                    .overlay {
                        if hex == selectedHex {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                    }
                    .onTapGesture { selectedHex = hex }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
