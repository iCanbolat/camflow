import SwiftUI

extension Color {
    /// Parses "#RRGGBB" / "RRGGBB" hex strings used by tag and label colors.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Preset palette offered when creating tags and labels.
enum TagPalette {
    static let colors: [String] = [
        "#FF6B35", // brand orange
        "#F7B32B", // amber
        "#2E933C", // green
        "#1B98E0", // blue
        "#6C63FF", // purple
        "#E0475B", // red
        "#13B5B1", // teal
        "#8D6E63", // brown
    ]
}
