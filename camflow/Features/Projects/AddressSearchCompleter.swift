import MapKit
import Observation

/// Wraps MKLocalSearchCompleter for the project address field, and resolves
/// a chosen completion into a display address + coordinate.
@Observable
final class AddressSearchCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()

    private(set) var results: [MKLocalSearchCompletion] = []

    var query = "" {
        didSet {
            if query.isEmpty {
                results = []
            } else {
                completer.queryFragment = query
            }
        }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }

    struct ResolvedAddress {
        let address: String
        let latitude: Double
        let longitude: Double
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> ResolvedAddress? {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        guard let item = try? await search.start().mapItems.first else { return nil }
        let coordinate = item.location.coordinate
        let address = completion.subtitle.isEmpty
            ? completion.title
            : "\(completion.title), \(completion.subtitle)"
        return ResolvedAddress(address: address, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
