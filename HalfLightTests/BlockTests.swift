//
//  BlockTests.swift
//  HalfLightTests
//
//  Covers person-to-person blocking: the block/unblock round trip through
//  `AuthService`, and the local cache purge that stops a blocked dreamer from
//  lingering on the device after the server has stopped serving them.
//
//  Like bans, the block is *enforced* in Postgres RLS (see the user_blocks
//  migration); these cover the client half.
//

import XCTest
import SwiftData
@testable import HalfLight

@MainActor
final class BlockTests: XCTestCase {

    private let mockKeys = [
        "mockAuthEmail", "mockBlockedUsernames", "userUsername", "userName",
    ]

    override func setUp() {
        super.setUp()
        mockKeys.forEach(UserDefaults.standard.removeObject(forKey:))
    }

    override func tearDown() {
        mockKeys.forEach(UserDefaults.standard.removeObject(forKey:))
        super.tearDown()
    }

    private func service() -> AuthService {
        UserDefaults.standard.set("dreamer@example.com", forKey: "mockAuthEmail")
        return AuthService(backend: MockAuthBackend())
    }

    // MARK: Block / unblock

    func testBlockingAddsToTheBlockList() async {
        let auth = service()

        let ok = await auth.blockUser(username: "rude_dreamer")

        XCTAssertTrue(ok)
        let blocked = await auth.blockedAccounts()
        XCTAssertEqual(blocked.map(\.username), ["rude_dreamer"])
    }

    /// Handles are case-insensitive, and blocking twice doesn't duplicate the row.
    func testBlockingTwiceIsIdempotent() async {
        let auth = service()

        await auth.blockUser(username: "Rude_Dreamer")
        await auth.blockUser(username: "rude_dreamer")

        let blocked = await auth.blockedAccounts()
        XCTAssertEqual(blocked.count, 1)
    }

    func testUnblockingRemovesThemFromTheList() async {
        let auth = service()
        await auth.blockUser(username: "rude_dreamer")
        await auth.blockUser(username: "someone_else")

        let ok = await auth.unblockUser(username: "rude_dreamer")

        XCTAssertTrue(ok)
        let blocked = await auth.blockedAccounts()
        XCTAssertEqual(blocked.map(\.username), ["someone_else"])
    }

    func testBlockListStartsEmpty() async {
        let blocked = await service().blockedAccounts()
        XCTAssertTrue(blocked.isEmpty)
    }

    // MARK: The local purge

    /// Blocking has to take the blocked dreamer off the device too — the server
    /// stops serving them, but the cache would keep showing them.
    func testPurgingAnAuthorRemovesEverythingOfTheirs() throws {
        let container = try ModelContainer(
            for: Dream.self, DeletedDream.self, FeedPost.self, Follow.self,
            Comment.self, AppNotification.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        UserDefaults.standard.set("dreamer", forKey: "userUsername")

        let theirPost = FeedPost(
            dreamID: UUID(), authorUsername: "rude_dreamer", authorName: "Rude",
            title: "Their dream", dreamDescription: "…"
        )
        let myPost = FeedPost(
            dreamID: UUID(), authorUsername: "dreamer", authorName: "Dreamer",
            title: "My dream", dreamDescription: "…"
        )
        context.insert(theirPost)
        context.insert(myPost)
        // A comment of theirs on *my* post — has to go even though the post stays.
        context.insert(Comment(
            postID: myPost.id, authorUsername: "Rude_Dreamer",
            authorName: "Rude", text: "something unpleasant"
        ))
        context.insert(Comment(
            postID: myPost.id, authorUsername: "friendly", authorName: "Friendly",
            text: "nice dream"
        ))
        context.insert(Follow(username: "rude_dreamer"))
        context.insert(Follow(username: "friendly"))
        try context.save()

        DreamStore(context: context).purgeAuthor(username: "rude_dreamer")

        XCTAssertEqual(
            try context.fetch(FetchDescriptor<FeedPost>()).map(\.title),
            ["My dream"]
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<Comment>()).map(\.text),
            ["nice dream"],
            "Their comments go even when they're on someone else's post"
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<Follow>()).map(\.username),
            ["friendly"]
        )
    }

    /// A blocked dreamer's post takes its comment thread with it, rather than
    /// leaving orphaned comments keyed to a post that no longer exists.
    func testPurgingAnAuthorTakesTheirPostsCommentsToo() throws {
        let container = try ModelContainer(
            for: Dream.self, DeletedDream.self, FeedPost.self, Follow.self,
            Comment.self, AppNotification.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        UserDefaults.standard.set("dreamer", forKey: "userUsername")

        let theirPost = FeedPost(
            dreamID: UUID(), authorUsername: "rude_dreamer", authorName: "Rude",
            title: "Their dream", dreamDescription: "…"
        )
        context.insert(theirPost)
        context.insert(Comment(
            postID: theirPost.id, authorUsername: "friendly",
            authorName: "Friendly", text: "a comment on their post"
        ))
        try context.save()

        DreamStore(context: context).purgeAuthor(username: "rude_dreamer")

        XCTAssertTrue(try context.fetch(FetchDescriptor<FeedPost>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Comment>()).isEmpty)
    }
}
