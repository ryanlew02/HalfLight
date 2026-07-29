//
//  DreamAnalyzer.swift
//  HalfLight
//
//  Calls the Supabase Edge Functions that proxy to Claude:
//    - `analyze-dream` → an AI category + interpretation for a dream
//    - `suggest-tags`  → a few theme/symbol tags drawn from the dream text
//    - `suggest-title` → a short, evocative title for the dream
//  The Anthropic API key lives in the functions (server-side), never in the app.
//

import Foundation
#if canImport(Supabase)
import Supabase
#endif

/// An error payload (`{ "error": "…" }`) returned by the edge functions, used to
/// surface server-side messages like the daily AI limit.
private struct ServerError: Decodable {
    let error: String
}

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

/// The structured result returned by the suggest-title function.
private struct TitleSuggestion: Decodable {
    let title: String
}

@MainActor
@Observable
final class DreamAnalyzer {
    /// True while an analyze-dream request is in flight.
    private(set) var isAnalyzing = false
    /// True while a suggest-tags request is in flight.
    private(set) var isSuggestingTags = false
    /// True while a suggest-title request is in flight.
    private(set) var isSuggestingTitle = false
    /// A user-facing message when a request fails; `nil` when there's no error.
    private(set) var errorMessage: String?

    /// Called when the server refuses a request because it sees no subscription.
    /// Should push the device's entitlement to the server and report whether it
    /// landed; a `true` gets the request retried once. Set by the views that own a
    /// `SubscriptionManager`, so someone who subscribes mid-journal can use the AI
    /// features immediately rather than waiting for the entitlement to catch up.
    var recoverEntitlement: (() async -> Bool)?

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

    /// Suggest a short title drawn from the dream description. Returns `nil` (and
    /// sets `errorMessage`) on failure.
    func suggestTitle(entry: String, mood: String) async -> String? {
        isSuggestingTitle = true
        defer { isSuggestingTitle = false }
        return await post(
            function: "suggest-title",
            title: "",
            entry: entry,
            mood: mood,
            as: TitleSuggestion.self
        )?.title
    }

    // MARK: - Networking

    /// The three ways a request can end: with a value, refused as unsubscribed
    /// (which a just-completed purchase can heal), or failed for any other reason.
    private enum PostOutcome<T> {
        case success(T)
        case notSubscribed
        case failed
    }

    /// POST the dream to a Supabase Edge Function and decode its JSON response,
    /// re-registering the entitlement and trying once more if the server says the
    /// dreamer isn't subscribed.
    private func post<T: Decodable>(
        function: String,
        title: String,
        entry: String,
        mood: String,
        as type: T.Type
    ) async -> T? {
        switch await send(function: function, title: title, entry: entry, mood: mood, as: type) {
        case .success(let value):
            return value
        case .failed:
            return nil
        case .notSubscribed:
            // Most likely a purchase that hasn't reached the server yet. Push the
            // entitlement across and, if that works, run the request again — the
            // gate checks the subscription before spending a daily credit, so the
            // refused attempt cost the dreamer nothing.
            guard let recoverEntitlement, await recoverEntitlement() else { return nil }
            guard case .success(let value) = await send(
                function: function, title: title, entry: entry, mood: mood, as: type
            ) else { return nil }
            return value
        }
    }

    /// A single request to an AI edge function.
    private func send<T: Decodable>(
        function: String,
        title: String,
        entry: String,
        mood: String,
        as type: T.Type
    ) async -> PostOutcome<T> {
        errorMessage = nil

        // The functions verify the dreamer's JWT and enforce a per-user daily
        // limit, so the request must carry the signed-in user's access token.
        guard let accessToken = await currentAccessToken() else {
            errorMessage = "Sign in to use AI features."
            return .failed
        }

        let endpoint = SupabaseConfig.url
            .appendingPathComponent("functions/v1/\(function)")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Supabase routes by the project's publishable key; the function
        // authenticates the dreamer by the access token in Authorization.
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(
            ["title": title, "entry": entry, "mood": mood]
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "No response from the server."
                return .failed
            }
            guard (200..<300).contains(http.statusCode) else {
                // Surface the server's message (daily limit reached, sign-in
                // required, …) when it sends one.
                if let payload = try? JSONDecoder().decode(ServerError.self, from: data) {
                    errorMessage = payload.error
                } else {
                    errorMessage = "Request failed (\(http.statusCode)). Please try again."
                }
                // 402 is the gate's "no active subscription" — recoverable.
                return http.statusCode == 402 ? .notSubscribed : .failed
            }
            return .success(try JSONDecoder().decode(T.self, from: data))
        } catch is DecodingError {
            errorMessage = "Got an unexpected response from the server."
            return .failed
        } catch {
            errorMessage = "Couldn't reach the server. Check your connection."
            return .failed
        }
    }

    /// The signed-in dreamer's Supabase access token, or `nil` when signed out
    /// (or the backend isn't available), which gates the AI features.
    private func currentAccessToken() async -> String? {
        #if canImport(Supabase)
        return (try? await SupabaseClientProvider.shared.auth.session)?.accessToken
        #else
        return nil
        #endif
    }
}
