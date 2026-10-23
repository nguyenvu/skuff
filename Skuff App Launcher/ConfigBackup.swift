import Foundation

enum ConfigBackup {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent("Skuff/Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func save(tabs: [FolderTabRecord], settings: SkuffSettings) {
        guard let data = try? ConfigTransfer.exportData(tabs: tabs, settings: settings) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let file = directory.appendingPathComponent("skuff-\(stamp).json")
        try? data.write(to: file, options: .atomic)
        prune()
    }

    static func latestData() -> Data? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let newest = files
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .first
        guard let newest else { return nil }
        return try? Data(contentsOf: newest)
    }

    private static func prune() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let json = files
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
        for extra in json.dropFirst(5) {
            try? FileManager.default.removeItem(at: extra)
        }
    }
}

struct UndoBanner: Equatable {
    var message: String
    var token: UUID
    /// False for plain notices that have nothing to undo.
    var canUndo: Bool = true
}
