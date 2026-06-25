//
//  CommentsView.swift
//  HalfLight
//
//  The comments on a feed post, shown in a sheet from the card's comment button.
//  Lists existing comments and lets the dreamer add their own; the author snapshot
//  is read from the profile defaults, mirroring how posts are authored.
//

import SwiftUI
import SwiftData

struct CommentsView: View {
    let post: FeedPost

    @Environment(\.modelContext) private var modelContext
    @Environment(DreamStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userName") private var userName = "Dreamer"
    @AppStorage("userUsername") private var userUsername = ""
    @AppStorage("profilePhoto") private var profilePhoto: Data?

    @Query private var comments: [Comment]
    @State private var draft = ""
    @FocusState private var composerFocused: Bool
    /// The ranked order captured as ids, so liking a comment doesn't reshuffle the
    /// list under the reader; recomputed when the comment set changes or the sheet
    /// (re)appears. The view always renders live comments in this order.
    @State private var orderedIDs: [UUID] = []

    init(post: FeedPost) {
        self.post = post
        let postID = post.id
        _comments = Query(
            filter: #Predicate<Comment> { $0.postID == postID },
            sort: \.createdAt,
            order: .forward
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if comments.isEmpty {
                    emptyState
                } else {
                    commentList
                }
                composer
            }
            .background { DreamBackground() }
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                refreshRanking()
                store.reconcileComments(postID: post.id)
            }
            // Re-rank when comments are added/removed (e.g. the reconcile pulls more
            // in, or the dreamer posts one) — but not on every like, which would
            // reshuffle the list as the reader is reading it.
            .onChange(of: comments.count) { _, _ in refreshRanking() }
        }
    }

    private var navigationTitle: String {
        comments.count == 1 ? "1 Comment" : "\(comments.count) Comments"
    }

    /// Live comments in the last-computed ranked order; comments added/removed
    /// since are handled on the next `refreshRanking()`.
    private var rankedComments: [Comment] {
        let byID = Dictionary(comments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = orderedIDs.compactMap { byID[$0] }
        // Fall back to the query order before the first ranking pass runs.
        return ordered.isEmpty ? comments : ordered
    }

    private func refreshRanking() {
        orderedIDs = CommentRanker.rank(comments).map(\.id)
    }

    // MARK: - List

    private var commentList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DreamMetric.lg) {
                ForEach(rankedComments) { comment in
                    commentRow(comment)
                }
            }
            .padding(DreamMetric.screen)
        }
    }

    private func commentRow(_ comment: Comment) -> some View {
        HStack(alignment: .top, spacing: DreamMetric.md) {
            FeedAvatar(photoData: comment.authorPhoto, name: comment.authorName, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(comment.authorName)
                        .font(.dreamBody(13, .semibold))
                        .foregroundStyle(Color.dreamText)
                    Text("@\(comment.authorUsername)")
                        .font(.dreamCaption)
                        .foregroundStyle(Color.dreamPrimary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(comment.createdAt, format: .relative(presentation: .named))
                        .font(.dreamCaption)
                        .foregroundStyle(.secondary)
                }

                Text(comment.text)
                    .font(.dreamBodyText)
                    .foregroundStyle(Color.dreamText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            likeButton(comment)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            if isOwn(comment) {
                Button(role: .destructive) {
                    delete(comment)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func likeButton(_ comment: Comment) -> some View {
        Button {
            SoundManager.shared.play(comment.isLiked ? .tap : .shimmer)
            store.toggleCommentLike(comment)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: comment.isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .semibold))
                if comment.likeCount > 0 {
                    Text("\(comment.likeCount)")
                        .font(.dreamBody(12, .semibold))
                }
            }
            .foregroundStyle(comment.isLiked ? Color.dreamAccent : Color.dreamText.opacity(0.5))
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(comment.isLiked ? "Unlike comment" : "Like comment")
    }

    private var emptyState: some View {
        VStack(spacing: DreamMetric.sm) {
            Spacer()
            Image(systemName: "bubble.left")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.dreamPrimary)
            Text("No comments yet")
                .font(.dreamSectionHeader)
            Text("Be the first to share a thought.")
                .font(.dreamBodyText)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(DreamMetric.xl)
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: DreamMetric.sm) {
            TextField("Add a comment…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($composerFocused)
                .padding(.horizontal, DreamMetric.md)
                .padding(.vertical, DreamMetric.sm)
                .background(Color.dreamSurface, in: .capsule)

            Button(action: addComment) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Color.dreamPrimary : Color.dreamText.opacity(0.3))
            }
            .disabled(!canSend)
            .accessibilityLabel("Post comment")
        }
        .padding(DreamMetric.md)
        .background(.bar)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    private func addComment() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        store.addComment(to: post, text: trimmed)

        draft = ""
        composerFocused = false
        SoundManager.shared.play(.tap)
    }

    private func delete(_ comment: Comment) {
        store.deleteComment(comment, on: post)
        SoundManager.shared.play(.tap)
    }

    /// Whether the comment was written by the signed-in dreamer (deletable).
    private func isOwn(_ comment: Comment) -> Bool {
        let me = userUsername.isEmpty ? userName.lowercased() : userUsername
        return comment.authorUsername.lowercased() == me.lowercased()
    }
}
