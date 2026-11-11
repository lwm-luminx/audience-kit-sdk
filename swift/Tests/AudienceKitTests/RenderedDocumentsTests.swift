import Foundation
import Testing
@testable import AudienceKit

/// The documents the SDK builds from a `SchemaShape` (most of its reads) interpolate their fields, so
/// scripts/graphql/check.mjs can't read them from the source. This writes each one, as an audience with every module
/// would get it, to `$AUDIENCEKIT_DOCUMENTS_DIR/<Operation>.graphql` for CI to check against the API's schema and
/// complexity budget (scripts/graphql/complexity.mjs). Without the variable it only checks that each one renders.
struct RenderedDocumentsTests {
    static let documents: [(name: String, document: String)] = {
        let shape = SchemaShape.everything
        return [
            ("Venues", Queries.venues(shape)),
            ("People", Queries.people(shape)),
            ("Locales", Queries.locales(shape)),
            ("ClosestLocale", Queries.closestLocale(shape)),
            ("Events", Queries.events(shape)),
            ("Event", Queries.event(shape)),
            ("EventSeries", Queries.eventSeries(shape)),
            ("VenueDetail", Queries.venueDetail(shape)),
            ("VenueCover", Queries.venueCover(shape)),
            ("VenueOffers", Queries.venueOffers(shape)),
            ("Offices", Queries.offices(shape)),
            ("OfficeHolder", Queries.officeHolder(shape)),
            ("Articles", Queries.articles(shape)),
            ("Article", Queries.article(shape)),
            ("Publications", Queries.publications(shape)),
            ("Publication", Queries.publication(shape)),
            ("MyOpEds", Queries.myOpEds(shape)),
        ] + [ArticleTopic.venue("v"), .event("e"), .person("p"), .locale("l")].map { topic in
            ("ArticlesAbout\(Queries.articles(about: topic).type)", Queries.articles(about: topic).document(shape))
        }
    }()

    @Test func everyShapedDocumentRendersAndIsWritten() throws {
        for (name, document) in Self.documents {
            #expect(document.contains("{"), "\(name) is empty")
            #expect(!document.contains("\\("), "\(name) has an unresolved interpolation")
        }
        guard let directory = ProcessInfo.processInfo.environment["AUDIENCEKIT_DOCUMENTS_DIR"] else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, document) in Self.documents {
            try document.write(to: url.appendingPathComponent("\(name).graphql"), atomically: true, encoding: .utf8)
        }
    }
}
