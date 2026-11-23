import AudienceCore
import Foundation
import Testing

private let publishersJSON = """
    {"soapbox":{"myPublications":[
     {"id":"p-q","name":"QSaltLake","masthead":null,"trust":"TRUSTED","person":{"id":"x-q","name":"QSaltLake"},
      "locale":{"id":"l-slc","name":"Salt Lake City","ancestors":[{"id":"l-us","name":"United States"},{"id":"l-ut","name":"Utah"}],
      "location":{"point":"POINT (-111.891 40.7608)"}}},
     {"id":"p-o","name":"Ogden Outlook","masthead":"Ogden Outlook","trust":"PENDING","person":{"id":"x-o","name":"Weber Media"},
      "locale":{"id":"l-ogden","name":"Ogden","ancestors":[{"id":"l-us","name":"United States"},{"id":"l-ut","name":"Utah"}],
      "location":{"point":"POINT (-111.9738 41.223)"}}},
     {"id":"p-a","name":"The Advocate","masthead":null,"trust":"TRUSTED","person":null,"locale":null},
     {"id":"p-b","name":"Bay Area Reporter","masthead":null,"trust":"SUSPENDED","person":{"id":"x-b","name":""},
      "locale":{"id":"l-sf","name":"San Francisco","ancestors":[],"location":{"point":"POINT (-122.4194 37.7749)"}}},
     {"id":"p-e","name":"Équipe Québec","masthead":null,"trust":null,"person":null,
      "locale":{"id":"l-mtl","name":"Montréal","ancestors":null,"location":null}}
    ]}}
    """

private func directory() throws -> PublisherDirectory {
    try JSONDecoder().decode(PublisherChooserDocuments.PublishersResponse.self, from: Data(publishersJSON.utf8)).directory
}

@Test func publishersDecodeWithThePlaceTheyCover() throws {
    #expect(PublisherChooserDocuments.publishersQuery.hasPrefix("# endpoint: staff"))
    #expect(PublisherChooserDocuments.localesAtQuery.hasPrefix("# endpoint: staff"))
    let directory = try directory()
    #expect(directory.entries.map(\.name) == ["Bay Area Reporter", "Équipe Québec", "Ogden Outlook", "QSaltLake", "The Advocate"])

    let q = try #require(directory.entry("p-q"))
    #expect(q.place == "Salt Lake City, Utah")
    #expect(q.localeAncestors == ["Utah", "United States"])
    #expect(q.personName == nil) // the same as its name
    #expect(q.coordinate == Coordinate(latitude: 40.7608, longitude: -111.891))
    #expect(!q.isPending && !q.isSuspended)

    let ogden = try #require(directory.entry("p-o"))
    #expect(ogden.personName == "Weber Media")
    #expect(ogden.isPending)
    #expect(directory.entry("p-b")?.isSuspended == true)
    #expect(directory.entry("p-b")?.personName == nil)
    #expect(directory.entry("p-b")?.place == "San Francisco")
    #expect(directory.entry("p-a")?.place == nil)
    #expect(directory.entry("p-e")?.coordinate == nil)
    #expect(directory.entry("missing") == nil)
    #expect(directory.entries(["p-a", "gone", "p-q"]).map(\.id) == ["p-a", "p-q"])
}

@Test func searchRanksNamesThenPeopleThenPlaces() throws {
    let directory = try directory()
    #expect(directory.search("  ").count == 5)
    #expect(directory.search("qsaltlake").map(\.id) == ["p-q"])
    #expect(directory.search("the").map(\.id).first == "p-a")
    #expect(directory.search("advocate").map(\.id) == ["p-a"]) // a word in the name
    #expect(directory.search("reporte").map(\.id) == ["p-b"])
    #expect(directory.search("outlo").map(\.id) == ["p-o"])
    #expect(directory.search("weber").map(\.id) == ["p-o"]) // its person
    #expect(directory.search("salt lake city").map(\.id) == ["p-q"]) // its place
    #expect(directory.search("utah").map(\.id) == ["p-o", "p-q"]) // the place above, by name
    #expect(directory.search("equipe").map(\.id) == ["p-e"]) // accents ignored
    #expect(directory.search("montreal").map(\.id) == ["p-e"])
    #expect(directory.search("lake").map(\.id) == ["p-q"]) // "lake" inside the name ranks above places
    #expect(directory.search("nowhere").isEmpty)
}

@Test func nearbyPutsTheLocalesYoureInFirstThenTheClosest() throws {
    let directory = try directory()
    let downtownSLC = Coordinate(latitude: 40.76, longitude: -111.89)

    // Inside Salt Lake City (and Utah): QSaltLake first, then Ogden by distance. San Francisco is too far.
    let near = directory.nearby(downtownSLC, containing: ["l-us", "l-ut", "l-slc"])
    #expect(near.map(\.id) == ["p-q", "p-o"])
    #expect(near[0].inside)
    #expect(!near[1].inside)
    #expect((near[1].distance ?? 0) > 50_000 && (near[1].distance ?? 0) < 60_000)

    // Without containment, by distance only; a tight radius leaves Ogden out.
    #expect(directory.nearby(downtownSLC).map(\.id) == ["p-q", "p-o"])
    #expect(directory.nearby(downtownSLC, radius: 10_000).map(\.id) == ["p-q"])
    #expect(directory.nearby(downtownSLC, limit: 1).map(\.id) == ["p-q"])
    // A locale with no point still counts when you're in it.
    let inMontreal = directory.nearby(Coordinate(latitude: 45.5, longitude: -73.57), containing: ["l-mtl"])
    #expect(inMontreal.map(\.id) == ["p-e"])
    #expect(inMontreal[0].distance == nil)
    #expect(PublisherDirectory.distance(downtownSLC, downtownSLC) == 0)
}

@Test func recentsKeepTheLastSixNewestFirst() throws {
    let defaults = try #require(UserDefaults(suiteName: "PublisherChooserTests.\(UUID().uuidString)"))
    let recents = PublisherRecents(audienceID: "aud-1", defaults: defaults)
    #expect(recents.ids().isEmpty)
    recents.record("")
    #expect(recents.ids().isEmpty)
    for id in ["a", "b", "c", "d", "e", "f", "g"] { recents.record(id) }
    #expect(recents.ids() == ["g", "f", "e", "d", "c", "b"])
    recents.record("d")
    #expect(recents.ids() == ["d", "g", "f", "e", "c", "b"])
    #expect(PublisherRecents(audienceID: "aud-2", defaults: defaults).ids().isEmpty)
    recents.clear()
    #expect(recents.ids().isEmpty)
    #expect(PublisherRecents.adding("x", to: ["y", "x"]) == ["x", "y"])
}

@Test func localesAtDecodesOutermostFirst() throws {
    let response = try JSONDecoder().decode(PublisherChooserDocuments.LocalesAtResponse.self,
                                            from: Data(#"{"locales":[{"id":"l-us"},{"id":"l-ut"}]}"#.utf8))
    #expect(response.ids == ["l-us", "l-ut"])
}
