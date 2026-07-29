//
//  BanTests.swift
//  HalfLightTests
//
//  Covers banning a dreamer out of the shared feed: how a ban row is read into
//  `AuthService.isBanned` (which drives the feed's banned gate), and the local
//  cache wipe that stops the last feed pull from staying browsable offline.
//
//  The ban is *enforced* in Postgres RLS (see the user_bans migration) — these
//  tests cover the client half, which exists to explain the ban rather than to
//  impose it.
//

import XCTest
import SwiftData
@testable import HalfLight

@MainActor
final class BanTests: XCTestCase {

    private let mockKeys = [
        "mockAuthEmail", "mockAuthProvider", "mockBanned", "mockBanReason",
        "userUsername", "userName", "userFirstName",
    ]

    override func setUp() {
        super.setUp()
        mockKeys.forEach(UserDefaults.standard.removeObject(forKey:))
    }

    override func tearDown() {
        mockKeys.forEach(UserDefaults.standard.removeObject(forKey:))
        super.tearDown()
    }

    // MARK: BanInfo

    func testPermanentBanIsActive() {
        XCTAssertTrue(BanInfo(reason: "slurs", expiresAt: nil).isActive)
    }

    func testFutureExpiryIsStillActive() {
        let ends = Date().addingTimeInterval(60 * 60)
        XCTAssertTrue(BanInfo(reason: "spam", expiresAt: ends).isActive)
    }

    /// A lapsed ban is history, not a ban — the dreamer is back in.
    func testExpiredBanIsNotActive() {
        let ended = Date().addingTimeInterval(-60)
        XCTAssertFalse(BanInfo(reason: "spam", expiresAt: ended).isActive)
    }

    // MARK: AuthService

    /// A signed-in dreamer with a ban row is banned — this is what closes the feed.
    private func signedInService(banned: Bool, reason: String? = nil) async -> AuthService {
        let defaults = UserDefaults.standard
        defaults.set("dreamer@example.com", forKey: "mockAuthEmail")
        defaults.set("dreamer", forKey: "userUsername")
        defaults.set(banned, forKey: "mockBanned")
        if let reason { defaults.set(reason, forKey: "mockBanReason") }
        let auth = AuthService(backend: MockAuthBackend())
        await auth.restore()
        return auth
    }

    func testSignedInDreamerWithABanIsBanned() async {
        let auth = await signedInService(banned: true, reason: "Repeatedly posting slurs")

        XCTAssertTrue(auth.isSignedIn)
        XCTAssertTrue(auth.isBanned)
        XCTAssertEqual(auth.ban?.reason, "Repeatedly posting slurs")
    }

    func testSignedInDreamerWithoutABanIsNotBanned() async {
        let auth = await signedInService(banned: false)

        XCTAssertTrue(auth.isSignedIn)
        XCTAssertFalse(auth.isBanned)
        XCTAssertNil(auth.ban)
    }

    /// A ban landing mid-session is picked up by the feed's refresh, without a
    /// relaunch — that's the path a live ban actually travels.
    func testBanLandingMidSessionIsPickedUpOnRefresh() async {
        let auth = await signedInService(banned: false)
        XCTAssertFalse(auth.isBanned)

        UserDefaults.standard.set(true, forKey: "mockBanned")
        await auth.refreshBan()

        XCTAssertTrue(auth.isBanned)
    }

    /// And lifting it lets them straight back in.
    func testUnbanRestoresAccessOnRefresh() async {
        let auth = await signedInService(banned: true)
        XCTAssertTrue(auth.isBanned)

        UserDefaults.standard.set(false, forKey: "mockBanned")
        await auth.refreshBan()

        XCTAssertFalse(auth.isBanned)
    }

    /// Being signed out isn't being banned — the sign-in gate handles that case.
    func testSignedOutIsNotBanned() async {
        UserDefaults.standard.set(true, forKey: "mockBanned")
        let auth = AuthService(backend: MockAuthBackend())
        await auth.restore()

        XCTAssertFalse(auth.isSignedIn)
        XCTAssertFalse(auth.isBanned)
    }

    // MARK: The local cache wipe

    /// A ban has to take the cached feed with it, or the last pull stays readable
    /// offline. The dreamer's own journal and their own posts must survive.
    func testWipingTheSocialCacheLeavesTheDreamersOwnThingsAlone() throws {
        let container = try ModelContainer(
            for: Dream.self, DeletedDream.self, FeedPost.self, Follow.self,
            Comment.self, AppNotification.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        UserDefaults.standard.set("dreamer", forKey: "userUsername")
        UserDefaults.standard.set("Dreamer", forKey: "userName")

        let mine = FeedPost(
            dreamID: UUID(), authorUsername: "dreamer", authorName: "Dreamer",
            title: "My shared dream", dreamDescription: "…"
        )
        let theirs = FeedPost(
            dreamID: UUID(), authorUsername: "someone_else", authorName: "Someone Else",
            title: "Their dream", dreamDescription: "…"
        )
        context.insert(mine)
        context.insert(theirs)
        context.insert(Dream(title: "A private dream", entry: "Only mine", date: .now, mood: .vivid))
        context.insert(Comment(
            postID: theirs.id, authorUsername: "someone_else",
            authorName: "Someone Else", text: "a comment"
        ))
        context.insert(Follow(username: "someone_else"))
        try context.save()

        DreamStore(context: context).wipeSocialCache()

        let posts = try context.fetch(FetchDescriptor<FeedPost>())
        XCTAssertEqual(posts.map(\.title), ["My shared dream"], "Own posts mirror the journal and stay")
        XCTAssertTrue(try context.fetch(FetchDescriptor<Comment>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Follow>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<AppNotification>()).isEmpty)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<Dream>()).map(\.title),
            ["A private dream"],
            "A ban must never touch the dreamer's own journal"
        )
    }
}
