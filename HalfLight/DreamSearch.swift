//
//  DreamSearch.swift
//  HalfLight
//
//  Smarter journal search. Two ideas on top of plain substring matching:
//    1. Order-independent word matching — the query is split into meaningful
//       words (filler words dropped), so "with garden" still finds "garden just".
//    2. Synonym expansion — Apple's on-device English word embedding surfaces
//       dreams that mean the same thing even when the wording differs.
//  Pure functions over a dream's text; no network, works fully offline.
//

import Foundation
import NaturalLanguage

enum DreamSearch {
    /// Common words ignored when tokenizing, so a query like "with garden"
    /// effectively searches for just "garden".
    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "of", "to", "in", "on", "at", "is", "it",
        "its", "with", "for", "but", "was", "were", "that", "this", "my", "me",
        "i", "we", "as", "by", "from", "into", "over", "under", "then", "than",
        "so", "im", "are", "be", "been", "had", "has", "have", "about"
    ]

    /// Apple's English word embedding, loaded once. `nil` when unavailable, in
    /// which case synonym expansion is simply skipped and matching still works.
    private static let embedding = NLEmbedding.wordEmbedding(for: .english)

    /// Apple's English sentence embedding, for true semantic ("vibe") matching.
    /// `nil` when unavailable, in which case semantic ranking is skipped.
    private static let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)

    /// Break text into meaningful lowercase word tokens (filler words removed).
    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopWords.contains($0) }
    }

    /// Relevance of one dream for the query. `0` means no match; higher is more
    /// relevant. Whole-query and title hits always outrank synonym hits, so an
    /// exact search never gets buried under fuzzy matches.
    static func score(for dream: Dream, query: String, includeSynonyms: Bool) -> Double {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return 1 }

        let title = dream.title.lowercased()
        let entry = dream.entry.lowercased()
        let mood = dream.mood.rawValue.lowercased()
        let tags = dream.tags.map { $0.lowercased() }
        let themes = dream.aiThemes.map { $0.lowercased() }
        let haystack = ([title, entry, mood] + tags + themes).joined(separator: " ")

        var score = 0.0

        // Whole-query phrase match — the strongest signal.
        if haystack.contains(trimmed) { score += 10 }

        let tokens = tokenize(trimmed)
        for token in tokens {
            if title.contains(token) {
                score += 4
            } else if tags.contains(where: { $0.contains(token) })
                        || themes.contains(where: { $0.contains(token) }) {
                score += 3
            } else if entry.contains(token) || mood.contains(token) {
                score += 2
            }
        }

        // Related-word matches, weighted low so they surface relevant dreams
        // without ever outranking a literal hit.
        if includeSynonyms {
            for synonym in synonyms(for: tokens) where haystack.contains(synonym) {
                score += 0.5
            }
        }

        return score
    }

    /// The nearest related words for each token, from the word embedding. Excludes
    /// the words the user already typed so they aren't double-counted.
    private static func synonyms(for tokens: [String]) -> Set<String> {
        guard let embedding else { return [] }
        var related: Set<String> = []
        for token in tokens {
            for (word, distance) in embedding.neighbors(for: token, maximumCount: 5)
            where distance < 1.0 {
                related.insert(word)
            }
        }
        return related.subtracting(tokens)
    }

    // MARK: - Semantic (sentence-level) search

    /// The text used to represent a dream when embedding it for semantic search.
    static func indexText(for dream: Dream) -> String {
        ([dream.title, dream.entry, dream.mood.rawValue] + dream.tags + dream.aiThemes)
            .joined(separator: ". ")
    }

    /// A sentence-embedding vector for free text, or `nil` if the model is
    /// unavailable or the text is empty.
    static func sentenceVector(for text: String) -> [Double]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let sentenceEmbedding else { return nil }
        return sentenceEmbedding.vector(for: trimmed)
    }

    /// Cosine similarity of two equal-length vectors, in roughly `-1...1` (higher
    /// means more semantically alike). `0` when either vector is empty/zero.
    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in a.indices {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }
}
