//
//  FeedView.swift
//  HalfLight
//
//  The social feed of dreams: browse other dreamers' shared dreams, open their
//  profiles, and leave comments. Intentionally blank for now — a placeholder tab
//  while the feed is built out.
//

import SwiftUI

struct FeedView: View {
    var body: some View {
        NavigationStack {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { DreamBackground() }
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview("Light") {
    FeedView()
}

#Preview("Dark") {
    FeedView()
        .preferredColorScheme(.dark)
}
