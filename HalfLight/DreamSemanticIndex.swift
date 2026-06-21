//
//  DreamSemanticIndex.swift
//  HalfLight
//
//  On-device semantic index for the journal. Caches one sentence-embedding vector
//  per dream so semantic ("search by vibe") ranking doesn't re-embed every dream
//  on each keystroke. Vectors are recomputed only when a dream's content changes,
//  and the embedding work happens off the main actor to keep typing smooth.
//

import Foundation
import Observation

@MainActor
@Observable
final class DreamSemanticIndex {
    /// dream id → (content hash, embedding vector). The hash lets us detect edits.
    private var cache: [UUID: (hash: Int, vector: [Double])] = [:]
    private var isIndexing = false
    /// Bumped whenever freshly-computed vectors land, so views that rank by
    /// similarity recompute once the background pass finishes.
    private(set) var version = 0

    /// The cached vector for a dream, if it's been indexed and is still current.
    func vector(for dream: Dream) -> [Double]? {
        guard let entry = cache[dream.id], entry.hash == Self.contentHash(dream) else {
            return nil
        }
        return entry.vector
    }

    /// Embed any dreams that are new or have changed since last time. Snapshots the
    /// text on the main actor (SwiftData models aren't safe to touch off it), then
    /// embeds the plain strings in the background and bumps `version` when done.
    func index(_ dreams: [Dream]) {
        guard !isIndexing else { return }

        let pending = dreams.compactMap { dream -> (id: UUID, hash: Int, text: String)? in
            let hash = Self.contentHash(dream)
            if cache[dream.id]?.hash == hash { return nil }
            return (dream.id, hash, DreamSearch.indexText(for: dream))
        }
        guard !pending.isEmpty else { return }

        isIndexing = true
        Task.detached(priority: .utility) {
            let computed = pending.compactMap { item -> (UUID, Int, [Double])? in
                guard let vector = DreamSearch.sentenceVector(for: item.text) else { return nil }
                return (item.id, item.hash, vector)
            }
            await MainActor.run {
                for (id, hash, vector) in computed {
                    self.cache[id] = (hash, vector)
                }
                self.isIndexing = false
                self.version &+= 1
            }
        }
    }

    /// Forget vectors for dreams that no longer exist, keeping the cache bounded.
    func prune(keeping dreams: [Dream]) {
        let live = Set(dreams.map(\.id))
        if cache.count != live.count {
            cache = cache.filter { live.contains($0.key) }
        }
    }

    private static func contentHash(_ dream: Dream) -> Int {
        var hasher = Hasher()
        hasher.combine(dream.title)
        hasher.combine(dream.entry)
        hasher.combine(dream.mood.rawValue)
        hasher.combine(dream.tags)
        hasher.combine(dream.aiThemes)
        return hasher.finalize()
    }
}
