import AppKit
import QuickLookThumbnailing

/// In-memory caches for folder tab icons and Quick Look thumbnails.
final class FolderThumbnails {
    static let shared = FolderThumbnails()

    private let thumbnails = NSCache<NSString, NSImage>()
    private let icons = NSCache<NSString, NSImage>()
    /// Files Quick Look has no real thumbnail for, so they are not asked for again.
    private var misses = Set<String>()

    init() {
        thumbnails.countLimit = 600
        icons.countLimit = 1500
    }

    func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let hit = icons.object(forKey: key) { return hit }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(image, forKey: key)
        return image
    }

    func thumbnail(for item: FolderItem, side: CGFloat, scale: CGFloat) async -> NSImage? {
        let key = cacheKey(item, side: side)
        if let hit = thumbnails.object(forKey: key as NSString) { return hit }
        guard !misses.contains(key) else { return nil }
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: side, height: side),
            scale: max(scale, 1),
            representationTypes: .thumbnail
        )
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            misses.insert(key)
            return nil
        }
        let image = representation.nsImage
        thumbnails.setObject(image, forKey: key as NSString)
        return image
    }

    func removeAll() {
        thumbnails.removeAllObjects()
        icons.removeAllObjects()
        misses.removeAll()
    }

    private func cacheKey(_ item: FolderItem, side: CGFloat) -> String {
        "\(item.url.path)|\(item.modified.timeIntervalSinceReferenceDate)|\(Int(side))"
    }
}
