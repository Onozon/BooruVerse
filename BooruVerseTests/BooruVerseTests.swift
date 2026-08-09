import XCTest
@testable import BooruVerse

final class BooruVerseTests: XCTestCase {

    // MARK: - Date parser

    func testDateParserUnixSeconds() {
        let date = BooruDateParser.parse("1700000000")
        XCTAssertEqual(date?.timeIntervalSince1970, 1_700_000_000)
    }

    func testDateParserUnixMilliseconds() {
        let date = BooruDateParser.parse("1700000000000")
        XCTAssertEqual(date?.timeIntervalSince1970, 1_700_000_000)
    }

    func testDateParserISO8601() {
        let date = BooruDateParser.parse("2023-11-14T22:13:20Z")
        XCTAssertNotNil(date)
        XCTAssertEqual(Int(date!.timeIntervalSince1970), 1_700_000_000)
    }

    func testDateParserEmpty() {
        XCTAssertNil(BooruDateParser.parse(nil))
        XCTAssertNil(BooruDateParser.parse(""))
        XCTAssertNil(BooruDateParser.parse("not-a-date"))
    }

    // MARK: - Rating

    func testSafeOnlyAllowsOnlySafe() {
        XCTAssertTrue(RatingFilter.safeOnly.allows(.safe))
        XCTAssertFalse(RatingFilter.safeOnly.allows(.sensitive))
        XCTAssertFalse(RatingFilter.safeOnly.allows(.questionable))
        XCTAssertFalse(RatingFilter.safeOnly.allows(.explicit))
    }

    func testHideExplicitKeepsSensitive() {
        XCTAssertTrue(RatingFilter.hideExplicit.allows(.safe))
        XCTAssertTrue(RatingFilter.hideExplicit.allows(.sensitive))
        XCTAssertTrue(RatingFilter.hideExplicit.allows(.questionable))
        XCTAssertFalse(RatingFilter.hideExplicit.allows(.explicit))
    }

    func testDanbooruSafeOnlyQueryExcludesSensitive() {
        let tags = BrowseViewModel.query("", withRating: .safeOnly, flavor: .danbooru2)
        XCTAssertEqual(tags, "rating:g")
    }

    func testDanbooruHideExplicitQuery() {
        let tags = BrowseViewModel.query("cat", withRating: .hideExplicit, flavor: .danbooru2)
        XCTAssertEqual(tags, "cat rating:g,s,q")
    }

    func testMoebooruSafeOnlyQuery() {
        XCTAssertEqual(
            BrowseViewModel.query("", withRating: .safeOnly, flavor: .moebooru),
            "rating:s"
        )
    }

    // MARK: - Personal feed sort

    func testRecencySortNewestFirst() {
        let newer = makePost(id: 1, createdAt: Date(timeIntervalSince1970: 200))
        let older = makePost(id: 2, createdAt: Date(timeIntervalSince1970: 100))
        XCTAssertTrue(PersonalFeedAggregator.recencySort(newer, older))
        XCTAssertFalse(PersonalFeedAggregator.recencySort(older, newer))
    }

    func testRecencySortMissingDatesLast() {
        let dated = makePost(id: 1, createdAt: Date())
        let undated = makePost(id: 2, createdAt: nil)
        XCTAssertTrue(PersonalFeedAggregator.recencySort(dated, undated))
        XCTAssertFalse(PersonalFeedAggregator.recencySort(undated, dated))
    }

    // MARK: - Aggregator failures

    @MainActor
    func testPostFeedAggregatorThrowsWhenAllServersFail() async throws {
        let clients: [any BooruSite & BooruBrowsing] = [
            FailingBrowseSite(siteID: "a"),
            FailingBrowseSite(siteID: "b"),
        ]
        let aggregator = PostFeedAggregator(clients: clients, perServerLimit: 10)

        do {
            _ = try await aggregator.loadNextPage { _, _, _ in
                throw URLError(.timedOut)
            }
            XCTFail("Expected allServersFailed")
        } catch PostFeedAggregatorError.allServersFailed {
            // expected
        }
    }

    @MainActor
    func testPostFeedAggregatorSucceedsWhenOneServerWorks() async throws {
        let clients: [any BooruSite & BooruBrowsing] = [
            FailingBrowseSite(siteID: "a"),
            FailingBrowseSite(siteID: "b"),
        ]
        let aggregator = PostFeedAggregator(clients: clients, perServerLimit: 10)
        let post = makePost(id: 42, createdAt: Date())

        let page = try await aggregator.loadNextPage { client, _, _ in
            if client.siteID == "b" {
                return [post]
            }
            throw URLError(.timedOut)
        }
        XCTAssertEqual(page.map(\.globalID), [post.globalID])
    }

    // MARK: - Helpers

    private func makePost(id: Int, createdAt: Date?) -> BooruPost {
        BooruPost(
            serverID: "test",
            id: id,
            md5: "",
            tags: [],
            rating: .safe,
            score: 0,
            width: 100,
            height: 100,
            previewURL: nil,
            sampleURL: nil,
            fileURL: nil,
            fileExt: "jpg",
            sourceURL: nil,
            createdAt: createdAt
        )
    }
}

/// Minimal failing stub for aggregator tests.
nonisolated private struct FailingBrowseSite: BooruSite, BooruBrowsing {
    let siteID: String
    var displayName: String { siteID }
    var baseURL: URL { URL(string: "https://example.com")! }
    var apiFlavor: BooruAPIFlavor { .moebooru }

    func fetchPosts(tags: String, page: Int, limit: Int) async throws -> [BooruPost] {
        throw URLError(.timedOut)
    }

    func suggestTags(currentTags: [String], fragment: String, limit: Int) async throws -> [BooruTag] {
        []
    }

    func fetchTagIndexPage(page: Int, limit: Int) async throws -> [BooruTag] {
        []
    }

    func fetchTagTypes(for names: [String], onBatch: (@MainActor () -> Void)?) async -> [BooruTag] {
        []
    }
}
