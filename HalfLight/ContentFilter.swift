//
//  ContentFilter.swift
//  HalfLight
//
//  Client-side content moderation. Two strictness levels:
//
//    • Usernames & display names — the strict gate. Blocks *both* slurs/hate
//      terms and ordinary profanity; a handle or name is a permanent, public
//      label, so nothing crude belongs there.
//    • Published posts — the lenient gate. Blocks only slurs/hate terms. Swearing
//      is allowed (a dream is personal, and private dreams are never checked at
//      all) — we only stop content that's hateful toward a group.
//
//  Matching is obfuscation-aware: input is lowercased, common leetspeak
//  substitutions are folded (0→o, 1→i, 3→e, @→a, $→s, …), and a "compact" pass
//  strips every separator so spaced-out evasions ("n i g g e r", "f_u_c_k")
//  still match. Whole-word matching (plus a small allow-list) keeps innocuous
//  words that merely *contain* a banned substring — "class", "assassin",
//  "Scunthorpe" — from tripping the filter.
//

import Foundation

enum ContentFilter {

    /// The outcome of a moderation check.
    enum Result: Equatable {
        case clean
        /// The text was rejected; `reason` is a user-facing explanation.
        case blocked(reason: String)

        var isBlocked: Bool { if case .blocked = self { return true }; return false }
    }

    // MARK: - Public checks

    /// Strict check for a username handle. Blocks slurs *and* profanity. Because a
    /// handle has no spaces, this leans on the compact (separator-stripped) pass.
    static func checkUsername(_ raw: String) -> Result {
        if matches(raw, terms: hateTerms) {
            return .blocked(reason: "That username isn't allowed. Please choose another.")
        }
        if matches(raw, terms: profaneTerms) {
            return .blocked(reason: "Usernames can't contain profanity. Please choose another.")
        }
        return .clean
    }

    /// Strict check for a display name (first or last). Blocks slurs *and*
    /// profanity, the same as usernames.
    static func checkDisplayName(_ raw: String) -> Result {
        if matches(raw, terms: hateTerms) {
            return .blocked(reason: "That name isn't allowed. Please enter your real name.")
        }
        if matches(raw, terms: profaneTerms) {
            return .blocked(reason: "Names can't contain profanity. Please enter your real name.")
        }
        return .clean
    }

    /// Lenient check for a post that's about to be published to the feed. Only
    /// slurs / hate terms are blocked — ordinary swearing is allowed. Checks the
    /// title, body, and tags together.
    static func checkPost(title: String, body: String, tags: [String] = []) -> Result {
        let combined = ([title, body] + tags).joined(separator: " ")
        if matches(combined, terms: hateTerms) {
            return .blocked(
                reason: "This post contains a slur or hateful language and can't be shared to the feed. Swearing is fine — hate speech isn't. Edit it and try again."
            )
        }
        return .clean
    }

    // MARK: - Matching

    /// True when any banned `term` appears in `raw`, checked against both the
    /// leet-folded text (with word boundaries) and the compact separator-stripped
    /// text (substring), while sparing allow-listed innocuous words.
    private static func matches(_ raw: String, terms: Set<String>) -> Bool {
        let folded = fold(raw)                       // lowercased + leet, separators kept
        let compact = folded.filter(\.isLetter)      // every separator removed

        // Words present in the folded text, used for the allow-list exemption.
        let words = Set(folded.split { !$0.isLetter }.map(String.init))

        for term in terms {
            // 1) Whole-word match on the folded text — precise, avoids Scunthorpe.
            if containsWord(term, in: folded) { return true }

            // 2) Compact substring match — catches spaced/punctuated obfuscation
            //    ("s.l.u.r"). Restricted to terms of 4+ letters and skipped when
            //    the match is fully explained by an allow-listed word, so ordinary
            //    words don't trip it.
            if term.count >= 4, compact.contains(term) {
                if !isExplainedByAllowList(term, words: words) { return true }
            }
        }
        return false
    }

    /// Whole-word (boundary) match of `term` within already-folded `text`. The
    /// boundaries are "not a letter" so digits/punctuation still delimit a word.
    private static func containsWord(_ term: String, in text: String) -> Bool {
        let pattern = "(?<![a-z])\(NSRegularExpression.escapedPattern(for: term))(?![a-z])"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Whether a compact-substring hit for `term` is fully accounted for by an
    /// allow-listed word actually present in the text (so "assassin" doesn't get
    /// flagged for containing "ass").
    private static func isExplainedByAllowList(_ term: String, words: Set<String>) -> Bool {
        for safe in allowList where words.contains(safe) && safe.contains(term) {
            return true
        }
        return false
    }

    /// Lowercase and fold common leetspeak so obfuscated spellings still match.
    /// Non-letter separators are preserved here (the compact pass strips them).
    private static func fold(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(raw.count)
        for scalar in raw.lowercased().unicodeScalars {
            let c = Character(scalar)
            switch c {
            case "0": out.append("o")
            case "1", "|", "!": out.append("i")
            case "3": out.append("e")
            case "4", "@": out.append("a")
            case "5", "$": out.append("s")
            case "7": out.append("t")
            case "8": out.append("b")
            case "9": out.append("g")
            default: out.append(c)
            }
        }
        return out
    }

    // MARK: - Word lists

    /// Slurs and hate terms. Blocked in *every* surface — usernames, names, and
    /// published posts alike.
    static let hateTerms: Set<String> = loadList("blocked-terms")

    /// Ordinary profanity. Blocked in usernames and display names only — *not* in
    /// posts (where swearing is allowed).
    static let profaneTerms: Set<String> = loadList("profanity")

    /// Innocuous words that legitimately contain a banned substring. When one of
    /// these is present, the compact-substring pass won't flag it (the whole-word
    /// pass never would). Keeps the Scunthorpe problem in check.
    static let allowList: Set<String> = loadList("allowlist")

    /// Load a bundled `.txt` word list (see `HalfLight/Moderation/`). Lowercases
    /// and folds each line the same way input is folded, so a file authored in
    /// plain spelling still matches leetspeak input; blank lines and `#` comments
    /// are skipped. A missing resource degrades that one list to empty (the filter
    /// keeps working with the others) and trips a debug assertion so a build
    /// misconfiguration is caught during development.
    private static func loadList(_ name: String) -> Set<String> {
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "txt"),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            assertionFailure("ContentFilter: missing moderation list '\(name).txt' — check it's bundled as a resource.")
            return []
        }
        var terms = Set<String>()
        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let folded = fold(trimmed).filter { $0.isLetter || $0 == " " }
            if !folded.isEmpty { terms.insert(folded) }
        }
        return terms
    }
}
