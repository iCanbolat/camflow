import SwiftUI
import PhoneNumberKit

/// Thin wrapper around PhoneNumberKit. `PhoneNumberUtility` parses the bundled
/// metadata on init, so it's expensive to create — the whole app shares one
/// instance. The "region" governs how a number with no country code is parsed
/// and formatted; it comes from the device (carrier, else locale, else US).
@MainActor
enum PhoneNumbers {
    static let utility = PhoneNumberUtility()

    /// Device region used as the default country for a fresh number.
    static var deviceRegion: String { PhoneNumberUtility.defaultRegionCode() }

    /// "+90" style dial code for a region (locked prefix shown beside the field).
    static func dialCode(for region: String) -> String {
        utility.countryCode(for: region).map { "+\($0)" } ?? "+"
    }

    /// As-you-type national formatting — no country code, trunk "0" stripped:
    /// "5464539499" or "05464539499" → "546 453 94 99".
    static func formattedNational(_ input: String, region: String) -> String {
        PartialFormatter(utility: utility, defaultRegion: region, withPrefix: false)
            .formatPartial(input)
    }

    /// Example national number for the placeholder ("501 234 56 78").
    static func exampleNational(for region: String) -> String {
        guard let example = utility.getExampleNumber(forCountry: region, ofType: .mobile) else { return "" }
        return formattedNational(String(example.nationalNumber), region: region)
    }

    /// Digit count of the region's example mobile number, used to cap input so
    /// the user can't type past a valid-length number. Generous fallback when
    /// the region is unknown (E.164 allows up to 15 digits).
    static func maxNationalDigits(for region: String) -> Int {
        guard let example = utility.getExampleNumber(forCountry: region, ofType: .mobile) else { return 15 }
        return String(example.nationalNumber).count
    }

    /// Canonical E.164 ("+905464539499") from a national number + region, or
    /// `nil` if it isn't a valid number.
    static func e164(national input: String, region: String) -> String? {
        guard let number = try? utility.parse(input, withRegion: region, ignoreType: true) else { return nil }
        return utility.format(number, toType: .e164)
    }

    /// Pretty international form ("+90 546 453 94 99") for display. Returns `raw`
    /// unchanged when it isn't a parseable number.
    static func displayFormatted(_ raw: String) -> String {
        guard let number = try? utility.parse(raw, ignoreType: true) else { return raw }
        return utility.format(number, toType: .international)
    }

    static func isValid(_ raw: String) -> Bool {
        (try? utility.parse(raw, ignoreType: true)) != nil
    }

    /// Gate for "is this stored value OK to save/invite": empty (the field is
    /// optional) or a validated E.164. `PhoneNumberField` only writes the "+"
    /// form once a number passes validation, so partial/invalid entries — stored
    /// unprefixed — are rejected here.
    static func isAcceptable(_ stored: String) -> Bool {
        stored.isEmpty || (stored.hasPrefix("+") && isValid(stored))
    }
}

/// A phone-number entry field backed by PhoneNumberKit. The country dial code
/// (e.g. "+90") is a fixed, non-editable prefix locked to the device region (or
/// to an existing number's country when editing). The user types only the
/// national part: it's masked as they type, capped at the region's valid length,
/// and shown against an example placeholder. `text` receives the canonical E.164
/// once valid, the masked national text while incomplete, and "" when empty.
struct PhoneNumberField: View {
    private let titleKey: LocalizedStringKey
    @Binding var text: String

    /// Locked country region. Seeded from an existing number's country, else the
    /// device region; fixed once shown so the prefix can't be changed or deleted.
    @State private var region = PhoneNumbers.deviceRegion
    /// The national part shown/edited in the field (formatted for humans).
    @State private var national = ""
    @State private var isValid = false
    /// The last value this field wrote into `text`, so external updates (initial
    /// load, programmatic reset) can be told apart from our own write-backs.
    @State private var lastWritten: String?
    @FocusState private var isFocused: Bool

    init(_ titleKey: LocalizedStringKey, text: Binding<String>) {
        self.titleKey = titleKey
        self._text = text
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: PhoneNumbers.dialCode(for: region))
                .foregroundStyle(.secondary)
            TextField(text: $national, prompt: Text(verbatim: PhoneNumbers.exampleNational(for: region))) {
                Text(titleKey)
            }
            .labelsHidden()
            .textContentType(.telephoneNumber)
            .keyboardType(.phonePad)
            .focused($isFocused)
            .onChange(of: national) { old, new in apply(old: old, new: new) }
            statusIcon
        }
        // `initial: true` seeds from the stored value on appear; later firings
        // catch external changes (the parent loading an existing record).
        .onChange(of: text, initial: true) { _, newValue in seed(from: newValue) }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isValid {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if !national.isEmpty && !isFocused {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func seed(from stored: String) {
        guard stored != lastWritten else { return }
        if stored.isEmpty {
            region = PhoneNumbers.deviceRegion
            if !national.isEmpty { national = "" }
            isValid = false
        } else if let parsed = try? PhoneNumbers.utility.parse(stored, ignoreType: true) {
            // Existing valid number: lock the prefix to its own country.
            region = PhoneNumbers.utility.getRegionCode(of: parsed) ?? region
            national = PhoneNumbers.formattedNational(String(parsed.nationalNumber), region: region)
            isValid = true
        } else {
            national = PhoneNumbers.formattedNational(stored, region: region)
            isValid = false
        }
        lastWritten = stored
    }

    private func apply(old: String, new: String) {
        let formatted = PhoneNumbers.formattedNational(new, region: region)
        // Reject anything past the region's valid length by reverting the edit.
        if formatted.filter(\.isNumber).count > PhoneNumbers.maxNationalDigits(for: region) {
            if national != old { national = old }
            return
        }
        if formatted != new { national = formatted }

        let canonical = PhoneNumbers.e164(national: formatted, region: region)
        isValid = canonical != nil
        let newText = canonical ?? formatted
        lastWritten = newText
        if text != newText { text = newText }
    }
}
