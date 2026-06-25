//
//  AvatarImageCache.swift
//  HalfLight
//
//  A tiny in-memory cache of decoded avatar images. Profile photos are stored as
//  raw JPEG `Data` (in UserDefaults and on feed posts); decoding that to a
//  `UIImage` on every view render — and once per feed card — is wasted work that
//  shows up as scroll hitching. Keyed by the data itself, so the same photo is
//  decoded a single time and reused everywhere.
//

import Foundation

#if canImport(UIKit)
import UIKit

enum AvatarImageCache {
    private static let cache = NSCache<NSData, UIImage>()

    /// The decoded image for this photo data, decoding (and caching) on first use.
    /// Avatars are small cropped JPEGs, so decoding stays cheap; the win is not
    /// repeating it on every render and across every card showing the same author.
    static func image(for data: Data) -> UIImage? {
        let key = data as NSData
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
#endif
