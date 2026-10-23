import Foundation
import SwiftData

enum ConfigError: LocalizedError {
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "This file was written by a newer version of Skuff."
        }
    }
}

enum SettingsStore {
    static let settingsKey = "skuff.settings"
    static let anchorsKey = "skuff.screenAnchors"
    static let namesKey = "skuff.appNames"
    static let didOrganizeKey = "skuff.didAutoOrganize"

    static func load() -> SkuffSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              var settings = try? JSONDecoder().decode(SkuffSettings.self, from: data) else {
            return SkuffSettings()
        }
        settings.clamp()
        return settings
    }

    static func save(_ settings: SkuffSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }

    static func loadAnchors() -> [String: ScreenAnchor] {
        guard let data = UserDefaults.standard.data(forKey: anchorsKey),
              let anchors = try? JSONDecoder().decode([String: ScreenAnchor].self, from: data) else {
            return [:]
        }
        return anchors
    }

    static func saveAnchors(_ anchors: [String: ScreenAnchor]) {
        guard let data = try? JSONEncoder().encode(anchors) else { return }
        UserDefaults.standard.set(data, forKey: anchorsKey)
    }
}

enum ConfigTransfer {
    static func exportData(tabs: [FolderTabRecord], settings: SkuffSettings) throws -> Data {
        var images: [String: String] = [:]
        for tab in tabs {
            guard case .image(let filename) = tab.icon else { continue }
            let url = IconStore.directory.appendingPathComponent(filename)
            if let data = try? Data(contentsOf: url) {
                images[filename] = data.base64EncodedString()
            }
            if filename.lowercased().hasSuffix(".svg") {
                let preview = url.deletingPathExtension().appendingPathExtension("preview.png")
                if let data = try? Data(contentsOf: preview) {
                    images[preview.lastPathComponent] = data.base64EncodedString()
                }
            }
        }
        let document = SkuffDocument(
            version: 1,
            tabs: tabs.map { $0.snapshot() },
            settings: settings,
            images: images
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    @MainActor
    static func importDocument(_ data: Data, into store: LibraryStore) throws {
        let document = try JSONDecoder().decode(SkuffDocument.self, from: data)
        guard document.version == 1 else { throw ConfigError.unsupportedVersion }
        // Write icons before touching the database so a failed write leaves the tabs intact.
        try IconStore.replaceAll(with: document.images)
        for tab in store.tabs {
            store.context.delete(tab)
        }
        var seen = Set<UUID>()
        for snapshot in document.tabs {
            guard seen.insert(snapshot.id).inserted else { continue }
            let record = FolderTabRecord(
                id: snapshot.id,
                kind: snapshot.kind,
                title: snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : snapshot.title,
                colorHex: SkuffColor(hex: snapshot.colorHex).hex,
                sortOrder: snapshot.sortOrder,
                categoryKey: snapshot.categoryKey
            )
            record.fontName = snapshot.fontName
            record.fontSize = snapshot.fontSize
            record.fontWeight = snapshot.fontWeight
            record.appBundleIDs = snapshot.appBundleIDs.filter { !$0.isEmpty }
            record.pinnedAppBundleIDs = snapshot.pinnedAppBundleIDs.filter { record.appBundleIDs.contains($0) }
            record.folderRelativePaths = snapshot.folderRelativePaths
            record.filter = snapshot.filter
            record.folderSource = snapshot.folderSource
            record.isPinned = snapshot.isPinned
            record.updatedAt = snapshot.updatedAt
            switch snapshot.icon {
            case .image(let filename):
                if IconStore.image(named: filename) != nil {
                    record.icon = .image(filename)
                } else {
                    record.icon = .sfSymbol("folder")
                }
            case .some(let icon):
                record.icon = icon
            case nil:
                record.icon = nil
            }
            store.context.insert(record)
        }
        var settings = document.settings
        settings.clamp()
        do {
            try store.context.save()
        } catch {
            store.context.rollback()
            store.reload()
            throw error
        }
        store.replaceSettings(settings)
        store.reload()
        store.refreshHotkeys()
        store.onChange?()
    }
}
