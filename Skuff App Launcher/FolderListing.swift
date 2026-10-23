import AppKit
import Foundation
import UniformTypeIdentifiers

nonisolated struct FolderItem: Identifiable, Hashable, Sendable {
    var url: URL
    var name: String
    var isDirectory: Bool
    var modified: Date
    var size: Int64
    var contentMatch: Bool = false
    var id: String { url.path }
}

nonisolated enum FolderListingError: Equatable, Sendable {
    case missing
    case denied
    case empty
}

nonisolated struct FolderSnapshot: Sendable {
    var items: [FolderItem]
    /// Entries on disk after hidden/excluded filtering, before the `cap`.
    var total: Int
    var recent: [FolderItem]
    var error: FolderListingError?
}

nonisolated enum FolderListing {
    /// Upper bound on entries read from one directory; the UI pages through these.
    static let cap = 5000

    static func kind(of url: URL, isDirectory: Bool) -> FileKind {
        if isDirectory { return .folders }
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .images }
        if type.conforms(to: .sourceCode) || ["swift", "m", "h", "js", "ts", "py", "rb", "go", "rs", "java"].contains(url.pathExtension.lowercased()) {
            return .code
        }
        if type.conforms(to: .archive) { return .archives }
        return .documents
    }

    static func matches(_ item: FolderItem, filters: [FileKind]) -> Bool {
        // Empty typeFilter means "no filter" — show every item.
        guard !filters.isEmpty else { return true }
        return filters.contains(kind(of: item.url, isDirectory: item.isDirectory))
    }

    /// Reads one directory plus its recent files. Safe to call off the main thread.
    static func snapshot(url: URL, source: FolderSource) -> FolderSnapshot {
        do {
            let (items, total) = try list(url: url, source: source)
            let recents = recent(url: url, source: source)
            return FolderSnapshot(items: items, total: total, recent: recents, error: items.isEmpty ? .empty : nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return FolderSnapshot(items: [], total: 0, recent: [], error: .missing)
        } catch {
            return FolderSnapshot(items: [], total: 0, recent: [], error: .denied)
        }
    }

    static func list(url: URL, source: FolderSource, limit: Int = cap) throws -> (items: [FolderItem], total: Int) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey, .contentModificationDateKey, .fileSizeKey, .nameKey]
        let children = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: source.showHidden ? [] : [.skipsHiddenFiles]
        )
        var items: [FolderItem] = []
        items.reserveCapacity(min(limit, children.count))
        var total = 0
        for child in children {
            let values = try? child.resourceValues(forKeys: Set(keys))
            let name = values?.name ?? child.lastPathComponent
            if source.excludedNames.contains(name) { continue }
            let hidden = values?.isHidden ?? false
            if hidden && !source.showHidden { continue }
            total += 1
            guard items.count < limit else { continue }
            // Packages such as .app or .key open like files rather than folders.
            let isDir = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
            items.append(
                FolderItem(
                    url: child,
                    name: name,
                    isDirectory: isDir,
                    modified: values?.contentModificationDate ?? .distantPast,
                    size: Int64(values?.fileSize ?? 0)
                )
            )
        }
        return (items, total)
    }

    static func recent(url: URL, source: FolderSource, now: Date = Date()) -> [FolderItem] {
        let cutoff = now.addingTimeInterval(-14 * 24 * 60 * 60)
        var found: [FolderItem] = []
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey, .contentModificationDateKey, .fileSizeKey, .nameKey],
            options: source.showHidden ? [.skipsPackageDescendants] : [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        var visited = 0
        while let file = enumerator?.nextObject() as? URL {
            visited += 1
            if visited > 2000 { break }
            let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey, .contentModificationDateKey, .fileSizeKey, .nameKey])
            let name = values?.name ?? file.lastPathComponent
            if source.excludedNames.contains(name) {
                if values?.isDirectory == true { enumerator?.skipDescendants() }
                continue
            }
            if values?.isDirectory == true { continue }
            guard let modified = values?.contentModificationDate, modified >= cutoff else { continue }
            found.append(
                FolderItem(
                    url: file,
                    name: name,
                    isDirectory: false,
                    modified: modified,
                    size: Int64(values?.fileSize ?? 0)
                )
            )
        }
        return Array(found.sorted { $0.modified > $1.modified }.prefix(6))
    }

    static func searchNames(root: URL, query: String, source: FolderSource, limit: Int = 200) -> [FolderItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else { return [] }
        var found: [FolderItem] = []
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey, .contentModificationDateKey, .fileSizeKey, .nameKey],
            options: source.showHidden ? [.skipsPackageDescendants] : [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        var visited = 0
        while let file = enumerator?.nextObject() as? URL {
            visited += 1
            if visited > 5000 { break }
            if (file.pathComponents.count - root.pathComponents.count) > 4 {
                enumerator?.skipDescendants()
                continue
            }
            let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .nameKey, .contentModificationDateKey, .fileSizeKey])
            let name = values?.name ?? file.lastPathComponent
            if source.excludedNames.contains(name) {
                if values?.isDirectory == true { enumerator?.skipDescendants() }
                continue
            }
            guard name.localizedStandardContains(needle) else { continue }
            found.append(
                FolderItem(
                    url: file,
                    name: name,
                    isDirectory: values?.isDirectory ?? false,
                    modified: values?.contentModificationDate ?? .distantPast,
                    size: Int64(values?.fileSize ?? 0)
                )
            )
            if found.count >= limit { break }
        }
        return found
    }

    /// Folders always come first, like Finder's "Keep folders on top".
    static func sort(_ items: [FolderItem], key: FolderSortKey, ascending: Bool) -> [FolderItem] {
        let ordered: (FolderItem, FolderItem) -> Bool
        switch key {
        case .name:
            ordered = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .dateModified:
            ordered = { $0.modified < $1.modified }
        case .kind:
            ordered = {
                let order = $0.url.pathExtension.localizedStandardCompare($1.url.pathExtension)
                if order != .orderedSame { return order == .orderedAscending }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
        return items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return ascending ? ordered(lhs, rhs) : ordered(rhs, lhs)
        }
    }
}
