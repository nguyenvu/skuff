import AppKit
import CoreServices
import Foundation

enum AppCategories {
    static let priority = [
        "developer-tools", "productivity", "graphics-design", "business", "utilities",
        "photography", "video", "music", "social-networking", "finance", "education",
        "entertainment", "games", "lifestyle", "news", "reference", "health-fitness",
        "medical", "sports", "travel", "weather", "shopping", "food-and-drink", "other"
    ]

    static func normalize(_ raw: String) -> String {
        var value = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "public.app-category."
        if value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        if value.contains("game") { return "games" }
        switch value {
        case "design", "graphics": return "graphics-design"
        case "developer": return "developer-tools"
        case "social": return "social-networking"
        case "": return "other"
        default: return value
        }
    }

    static func title(_ key: String) -> String {
        switch key {
        case "developer-tools": "Dev"
        case "productivity": "Office"
        case "graphics-design": "Design"
        case "business": "Business"
        case "utilities": "Utilities"
        case "photography": "Photography"
        case "video": "Video"
        case "music": "Music"
        case "social-networking": "Social"
        case "finance": "Finance"
        case "education": "Education"
        case "entertainment": "Entertainment"
        case "games": "Games"
        case "lifestyle": "Lifestyle"
        case "news": "News"
        case "reference": "Reference"
        case "health-fitness": "Health"
        case "medical": "Medical"
        case "sports": "Sports"
        case "travel": "Travel"
        case "weather": "Weather"
        case "shopping": "Shopping"
        case "food-and-drink": "Food"
        case "other": "Other"
        default: key.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    static func symbol(_ key: String) -> String {
        switch key {
        case "developer-tools": "hammer"
        case "productivity": "briefcase"
        case "graphics-design": "paintbrush"
        case "business": "chart.bar"
        case "utilities": "wrench"
        case "photography": "photo"
        case "video": "film"
        case "music": "music.note"
        case "social-networking": "person.2"
        case "finance": "creditcard"
        case "education": "book"
        case "entertainment": "sparkles"
        case "games": "gamecontroller"
        case "lifestyle": "heart"
        case "news": "newspaper"
        case "reference": "books.vertical"
        case "health-fitness": "figure.run"
        case "medical": "cross.case"
        case "sports": "sportscourt"
        case "travel": "airplane"
        case "weather": "cloud.sun"
        case "shopping": "cart"
        case "food-and-drink": "fork.knife"
        default: "square.grid.2x2"
        }
    }

    static func rank(_ key: String) -> Int {
        if key == "other" { return 10_000 }
        return priority.firstIndex(of: key) ?? 5_000
    }
}

enum AppInspector {
    static func bundleID(of url: URL) -> String? {
        if let identifier = Bundle(url: url)?.bundleIdentifier, !identifier.isEmpty {
            return identifier
        }
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let dictionary = NSDictionary(contentsOf: plist) else { return nil }
        return dictionary["CFBundleIdentifier"] as? String
    }

    static func displayName(of url: URL) -> String {
        let bundle = Bundle(url: url)
        if let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !name.isEmpty {
            return name
        }
        if let name = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
            return name
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    static func category(of url: URL) -> String {
        let bundle = Bundle(url: url)
        if let raw = bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String {
            return AppCategories.normalize(raw)
        }
        let plist = url.appendingPathComponent("Contents/Info.plist")
        if let dictionary = NSDictionary(contentsOf: plist),
           let raw = dictionary["LSApplicationCategoryType"] as? String {
            return AppCategories.normalize(raw)
        }
        return "other"
    }

    static func isBackgroundOnly(_ url: URL) -> Bool {
        let bundle = Bundle(url: url)
        if let flag = bundle?.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool { return flag }
        if let flag = bundle?.object(forInfoDictionaryKey: "LSBackgroundOnly") as? String { return flag == "1" }
        return false
    }
}

final class AppLibrary {
    var onUpdate: (([String: InstalledApp]) -> Void)?
    private let query = NSMetadataQuery()
    private var queryStarted = false
    private var pending: Task<Void, Never>?

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryChanged(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryChanged(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        rescan()
        startQuery()
    }

    func rescan() {
        var found: [String: InstalledApp] = [:]
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        for root in roots {
            scan(root, depth: 0, into: &found)
        }
        if let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
            add(finder, to: &found)
        }
        mergeQuery(into: &found)
        onUpdate?(found)
    }

    private func startQuery() {
        guard !queryStarted else { return }
        queryStarted = true
        query.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
        query.searchScopes = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]
        query.notificationBatchingInterval = 0.4
        if !query.start() {
            queryStarted = false
        }
    }

    @objc private func queryChanged(_ notification: Notification) {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self.rescan()
        }
    }

    private func mergeQuery(into found: inout [String: InstalledApp]) {
        guard queryStarted, query.isStarted else { return }
        query.disableUpdates()
        query.enumerateResults { item, _, _ in
            guard let metadata = item as? NSMetadataItem else { return }
            guard let path = metadata.value(forAttribute: kMDItemPath as String) as? String else { return }
            self.add(URL(fileURLWithPath: path), to: &found)
        }
        query.enableUpdates()
    }

    private func scan(_ directory: URL, depth: Int, into found: inout [String: InstalledApp]) {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for child in children {
            if child.pathExtension.lowercased() == "app" {
                add(child, to: &found)
                continue
            }
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory && depth < 2 {
                scan(child, depth: depth + 1, into: &found)
            }
        }
    }

    private func add(_ url: URL, to found: inout [String: InstalledApp]) {
        guard url.pathExtension.lowercased() == "app" else { return }
        guard let bundleID = AppInspector.bundleID(of: url), !bundleID.isEmpty else { return }
        if bundleID == Bundle.main.bundleIdentifier { return }
        if AppInspector.isBackgroundOnly(url) { return }
        let app = InstalledApp(
            bundleID: bundleID,
            name: AppInspector.displayName(of: url),
            url: url,
            category: AppInspector.category(of: url)
        )
        if found[bundleID] == nil || url.path.hasPrefix("/Applications") {
            found[bundleID] = app
        }
    }
}
