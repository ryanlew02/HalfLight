//
//  ContentFilterTests.swift
//  HalfLightTests
//
//  Verifies the two-tier moderation: usernames/names block slurs AND profanity;
//  posts block only slurs (swearing is allowed). Also checks obfuscation folding
//  and that innocuous words containing a banned substring aren't flagged.
//

import XCTest
@testable import HalfLight

final class ContentFilterTests: XCTestCase {

    // MARK: - Usernames & names: strict (slurs + profanity)

    func testUsernameBlocksProfanity() {
        XCTAssertTrue(ContentFilter.checkUsername("fuck_dreams").isBlocked)
        XCTAssertTrue(ContentFilter.checkUsername("bigshit").isBlocked)
    }

    func testUsernameBlocksSlur() {
        XCTAssertTrue(ContentFilter.checkUsername("faggot99").isBlocked)
    }

    func testUsernameBlocksLeetspeakEvasion() {
        // f, u->folds nothing but c, k with 4->a etc.; "sh1t" -> "shit".
        XCTAssertTrue(ContentFilter.checkUsername("sh1t_lord").isBlocked)
        XCTAssertTrue(ContentFilter.checkUsername("f4ggot").isBlocked)
    }

    func testCleanUsernamePasses() {
        XCTAssertEqual(ContentFilter.checkUsername("moonwalker"), .clean)
        XCTAssertEqual(ContentFilter.checkUsername("dreamer_42"), .clean)
    }

    func testInnocuousWordsWithBannedSubstringPass() {
        // Compact-substring pass must not flag these (Scunthorpe problem).
        XCTAssertEqual(ContentFilter.checkUsername("assassin"), .clean)
        XCTAssertEqual(ContentFilter.checkUsername("classic_cocktail"), .clean)
        XCTAssertEqual(ContentFilter.checkDisplayName("Cummings"), .clean)
    }

    func testNameBlocksSlur() {
        XCTAssertTrue(ContentFilter.checkDisplayName("Retard").isBlocked)
    }

    // MARK: - Posts: lenient (slurs only; swearing allowed)

    func testPostAllowsSwearing() {
        XCTAssertEqual(
            ContentFilter.checkPost(title: "Damn scary dream", body: "It was fucking terrifying."),
            .clean
        )
    }

    func testPostBlocksSlur() {
        XCTAssertTrue(
            ContentFilter.checkPost(title: "A dream", body: "there was a faggot").isBlocked
        )
    }

    func testPostBlocksSpacedOutSlur() {
        // Compact pass strips separators: "f a g g o t" -> "faggot".
        XCTAssertTrue(
            ContentFilter.checkPost(title: "n i g g e r", body: "spaced out").isBlocked
        )
    }

    func testPostChecksTags() {
        XCTAssertTrue(
            ContentFilter.checkPost(title: "Dream", body: "clean body", tags: ["chink"]).isBlocked
        )
    }
}
