import AppKit
import Foundation

/// Folder access helper. If the app is later distributed through the Mac App Store,
/// App Sandbox becomes mandatory and these bookmarks plus
/// `com.apple.security.files.user-selected.read-only` (or read-write) are required.
enum FolderAccess {
    static func bookmark(for url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    struct Resolution {
        var url: URL
        /// Set when the stored bookmark was stale and a fresh one could be made.
        var refreshedBookmark: Data?
        var hasBookmark: Bool
    }

    static func resolve(_ source: FolderSource) -> URL? {
        resolution(for: source)?.url
    }

    static func resolution(for source: FolderSource) -> Resolution? {
        if let data = source.bookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                return Resolution(url: url, refreshedBookmark: stale ? bookmark(for: url) : nil, hasBookmark: true)
            }
        }
        let url = URL(fileURLWithPath: (source.path as NSString).expandingTildeInPath)
        guard exists(url) else { return nil }
        return Resolution(url: url, refreshedBookmark: nil, hasBookmark: false)
    }

    static func exists(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    @discardableResult
    static func start(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    static func stop(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    static func chooseFolder(startingAt start: URL? = nil, prompt: String = "Choose") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        if let start {
            panel.directoryURL = start
        }
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }

    static func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
