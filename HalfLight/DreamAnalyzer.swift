//
//  DreamAnalyzer.swift
//  HalfLight
//
//  Calls the Supabase Edge Functions that proxy to Claude:
//    - `analyze-dream` → an AI category + interpretation for a dream
//    - `suggest-tags`  → a few theme/symbol tags drawn from the dream text
//  The Anthropic API key lives in the functions (server-side), never in the app.
//

import Foundation

/// The structured result returned by the analyze-dream function.
struct DreamAnalysis: Decodable {
    let category: String
    let meaning: String
    /// The 2–3 central themes; optional so older deployments still decode.
    let themes: [String]?
}

/// The structured result returned by the suggest-tags function.
private struct TagSuggestion: Decodable {
    let tags: [String]
}

@MainActor
@Observable
final class DreamAnalyzer {
    /// True while an analyze-dream request is in flight.
    private(set) var isAnalyzing = false
    /// True while a suggest-tags request is in flight.
    private(set) var isSuggestingTags = false
    /// A user-facing message when a request fails; `nil` when there's no error.
    private(set) var errorMessage: String?

    /// Analyze a dream into a category + meaning. Returns `nil` (and sets
    /// `errorMessage`) on failure.
    func analyze(title: String, entry: String, mood: String) async -> DreamAnalysis? {
        isAnalyzing = true
        defer { isAnalyzing = false }
        return await post(
            function: "analyze-dream",
            title: title,
            entry: entry,
            mood: mood,
            as: DreamAnalysis.self
        )
    }

    /// Suggest a few tags drawn from the dream description. Returns `nil` (and
    /// sets `errorMessage`) on failure.
    func suggestTags(title: String, entry: String, mood: String) async -> [String]? {
        isSuggestingTags = true
        defer { isSuggestingTags = false }
        return await post(
            function: "suggest-tags",
            title: title,
            entry: entry,
            mood: mood,
            as: TagSuggestion.self
        )?.tags
    }

    // MARK: - Networking

    /// POST the dream to a Supabase Edge Function and decode its JSON response.
    private func post<T: Decodable>(
        function: String,
        title: String,
        entry: String,
        mood: String,
        as type: T.Type
    ) async -> T? {
        errorMessage = nil

        let endpoint = SupabaseConfig.url
            .appendingPathComponent("functions/v1/\(function)")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Supabase routes by the project's anon/publishable key.
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(
            ["title": title, "entry": entry, "mood": mood]
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "No response from the server."
                return nil
            }
            guard (200..<300).contains(http.statusCode) else {
                errorMessage = "Request failed (\(http.statusCode)). Please try again."
                return nil
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch is DecodingError {
            errorMessage = "Got an unexpected response from the server."
            return nil
        } catch {
            errorMessage = "Couldn't reach the server. Check your connection."
            return nil
        }
    }
}
