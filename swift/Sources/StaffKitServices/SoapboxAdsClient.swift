import Foundation
import AudienceCore
import StaffKitCore

// A Soapbox publication's ads, rate sheet and media library, and the audience's admins' review of its ads (the API's
// doc/SOAPBOX.md "Publisher ads and the media library"). The documents and models are the SDK's `SoapboxAds`
// (AudienceCore), shared with Android; this sends them on the staff endpoint.

/// A publication's ads, as its managers see them, with whether it sells ads and its rate sheet.
public struct SoapboxPublicationAds: Sendable, Hashable {
    public var ads: [PublisherAd]
    public var adsEnabled: Bool
    public var adsNeedReview: Bool
    public var rateSheet: PublicationRateSheet

    public init(ads: [PublisherAd] = [], adsEnabled: Bool = false, adsNeedReview: Bool = true,
                rateSheet: PublicationRateSheet = PublicationRateSheet()) {
        self.ads = ads; self.adsEnabled = adsEnabled; self.adsNeedReview = adsNeedReview; self.rateSheet = rateSheet
    }
}

/// A save that the API turned down, with its reasons in words.
public struct PublisherAdProblems: LocalizedError, Sendable, Hashable {
    public let problems: [String]
    public init(_ problems: [String]) { self.problems = problems }
    public var errorDescription: String? { problems.joined(separator: " ") }
}

extension SoapboxClient {
    // MARK: A publication's ads

    public func ads(publicationID: String) async throws -> SoapboxPublicationAds {
        let response = try await session.graphQL(SoapboxAds.adsQuery, variables: SoapboxAds.idVariables(publicationID),
                                                 as: SoapboxAds.AdsResponse.self)
        return SoapboxPublicationAds(ads: response.ads, adsEnabled: response.adsEnabled,
                                     adsNeedReview: response.adsNeedReview, rateSheet: response.rateSheet)
    }

    /// Saves a new or changed ad. A dry run checks it without saving: the answer's problems say what would stop it,
    /// and an empty list means it would save. A real save that the API turns down throws ``PublisherAdProblems``.
    @discardableResult
    public func saveAd(_ draft: PublisherAdDraft) async throws -> (ad: PublisherAd?, problems: [String]) {
        let response = try await session.graphQL(SoapboxAds.saveAdMutation, variables: SoapboxAds.saveAdVariables(draft),
                                                 as: SoapboxAds.SaveAdResponse.self)
        if !draft.dryRun, response.ad == nil, !response.problems.isEmpty { throw PublisherAdProblems(response.problems) }
        return (response.ad, response.problems)
    }

    public func deleteAd(id: String) async throws {
        struct Response: Decodable, Sendable {}
        _ = try await session.graphQL(SoapboxAds.deleteAdMutation, variables: SoapboxAds.idVariables(id), as: Response.self)
    }

    public func saveRateSheet(publicationID: String, _ sheet: PublicationRateSheet) async throws -> PublicationRateSheet {
        let response = try await session.graphQL(SoapboxAds.saveRateSheetMutation,
                                                 variables: SoapboxAds.rateSheetVariables(publicationID: publicationID, sheet: sheet),
                                                 as: SoapboxAds.RateSheetResponse.self)
        return response.rateSheet ?? sheet
    }

    // MARK: The media library

    public func media(publicationID: String) async throws -> [PublicationMediaItem] {
        try await session.graphQL(SoapboxAds.mediaQuery, variables: SoapboxAds.idVariables(publicationID),
                                  as: SoapboxAds.MediaResponse.self).media
    }

    /// `photo` is a data: URI or an https link.
    public func addMedia(publicationID: String, photo: String, altText: String? = nil, caption: String? = nil,
                         credit: String? = nil) async throws -> PublicationMediaItem? {
        try await session.graphQL(SoapboxAds.addMediaMutation,
                                  variables: SoapboxAds.addMediaVariables(publicationID: publicationID, photo: photo,
                                                                          altText: altText, caption: caption, credit: credit),
                                  as: SoapboxAds.MediaItemResponse.self).media
    }

    public func updateMedia(id: String, altText: String?, caption: String?, credit: String?) async throws -> PublicationMediaItem? {
        try await session.graphQL(SoapboxAds.updateMediaMutation,
                                  variables: SoapboxAds.updateMediaVariables(id: id, altText: altText, caption: caption,
                                                                             credit: credit),
                                  as: SoapboxAds.MediaItemResponse.self).media
    }

    public func deleteMedia(id: String) async throws {
        struct Response: Decodable, Sendable {}
        _ = try await session.graphQL(SoapboxAds.deleteMediaMutation, variables: SoapboxAds.idVariables(id), as: Response.self)
    }

    // MARK: The audience's admins

    /// The ads waiting for review, and which publications' ads the audience reviews.
    public func adReviewQueue() async throws -> (queue: [PublisherAd], mode: PublisherAdsMode) {
        let response = try await session.graphQL(SoapboxAds.reviewQueueQuery, as: SoapboxAds.ReviewQueueResponse.self)
        return (response.queue, response.mode)
    }

    public func reviewAd(id: String, approve: Bool, note: String? = nil) async throws -> PublisherAd? {
        try await session.graphQL(SoapboxAds.reviewAdMutation,
                                  variables: SoapboxAds.reviewVariables(id: id, approve: approve, note: note),
                                  as: SoapboxAds.ModerateAdResponse.self).ad
    }

    /// Takes a running ad down (or puts it back), with a note its publication sees.
    public func removeAd(id: String, removed: Bool = true, note: String? = nil) async throws -> PublisherAd? {
        try await session.graphQL(SoapboxAds.removeAdMutation,
                                  variables: SoapboxAds.removeVariables(id: id, removed: removed, note: note),
                                  as: SoapboxAds.ModerateAdResponse.self).ad
    }

    public func enableAds(publicationID: String, enabled: Bool) async throws {
        struct Response: Decodable, Sendable {}
        _ = try await session.graphQL(SoapboxAds.enableAdsMutation,
                                      variables: SoapboxAds.enableVariables(publicationID: publicationID, enabled: enabled),
                                      as: Response.self)
    }

    public func setPublisherAds(_ mode: PublisherAdsMode) async throws {
        struct Response: Decodable, Sendable {}
        _ = try await session.graphQL(SoapboxAds.setModeMutation, variables: SoapboxAds.modeVariables(mode), as: Response.self)
    }
}
