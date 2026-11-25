import Foundation

extension VenueWorkspace {
    public func matches(search: String) -> Bool {
        let terms = search.split(whereSeparator: \.isWhitespace)
        let text = [name, address, locale.name].compactMap { $0 }.joined(separator: " ")
        return terms.allSatisfy { text.localizedStandardContains(String($0)) }
    }

    /// GraphQL Geography is WKT, with longitude first. Missing or invalid points stay unsorted.
    public var coordinate: (latitude: Double, longitude: Double)? { wktCoordinate(point) }
}

/// A WKT point's coordinate, longitude first as GraphQL Geography writes it; nil for a missing or invalid point.
func wktCoordinate(_ point: String?) -> (latitude: Double, longitude: Double)? {
    guard let point else { return nil }
    let wkt = point.components(separatedBy: ";").last!.trimmingCharacters(in: .whitespacesAndNewlines)
    guard wkt.uppercased().hasPrefix("POINT"), let start = wkt.firstIndex(of: "("),
          let end = wkt.lastIndex(of: ")"), start < end else { return nil }
    let values = wkt[wkt.index(after: start)..<end].split(whereSeparator: \.isWhitespace)
    guard values.count == 2, let longitude = Double(values[0]), let latitude = Double(values[1]),
          longitude.isFinite, latitude.isFinite, (-180...180).contains(longitude),
          (-90...90).contains(latitude) else { return nil }
    return (latitude, longitude)
}
