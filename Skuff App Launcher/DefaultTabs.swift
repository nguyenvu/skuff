import AppKit
import Foundation

enum DefaultTabs {
    struct Recipe {
        var title: String
        var symbol: String
        var colorHex: String
        var categoryKeys: [String]
        var bundleIDs: [String]
    }

    struct Made {
        var title: String
        var symbol: String
        var colorHex: String
        var bundleIDs: [String]
    }

    static let recipes: [Recipe] = [
        Recipe(
            title: "Office",
            symbol: "briefcase",
            colorHex: "F6C6CE",
            categoryKeys: ["productivity", "business"],
            bundleIDs: [
                "com.apple.iWork.Pages", "com.apple.iWork.Numbers", "com.apple.iWork.Keynote",
                "com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint",
                "com.apple.Notes", "com.apple.mail", "com.apple.iCal"
            ]
        ),
        Recipe(
            title: "Utilities",
            symbol: "wrench",
            colorHex: "F8D7A8",
            categoryKeys: ["utilities"],
            bundleIDs: [
                "com.apple.finder", "com.apple.Terminal", "com.apple.systempreferences",
                "com.apple.ActivityMonitor", "com.apple.Console", "com.apple.calculator",
                "com.apple.Safari"
            ]
        ),
        Recipe(
            title: "Video",
            symbol: "film",
            colorHex: "F6E7A8",
            categoryKeys: ["video", "entertainment"],
            bundleIDs: [
                "com.apple.QuickTimePlayerX", "com.apple.TV", "com.apple.iMovie",
                "com.apple.FinalCut", "com.apple.Music"
            ]
        ),
        Recipe(
            title: "Dev",
            symbol: "hammer",
            colorHex: "CFE6C4",
            categoryKeys: ["developer-tools"],
            bundleIDs: [
                "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
                "com.apple.Terminal", "dev.warp.Warp-Stable"
            ]
        ),
        Recipe(
            title: "Design",
            symbol: "paintbrush",
            colorHex: "B9E0E2",
            categoryKeys: ["graphics-design"],
            bundleIDs: [
                "com.bohemiancoding.sketch3", "com.figma.Desktop", "com.adobe.Photoshop",
                "com.apple.Preview"
            ]
        ),
        Recipe(
            title: "Photography",
            symbol: "photo",
            colorHex: "C9D5F6",
            categoryKeys: ["photography"],
            bundleIDs: [
                "com.apple.Photos", "com.apple.Preview", "com.apple.PhotoBooth"
            ]
        )
    ]

    static func make(installed: [String: InstalledApp], palette: [String]) -> [Made] {
        let byCategory = Dictionary(grouping: installed.values, by: \.category)
        return recipes.enumerated().map { index, recipe in
            var ids: [String] = []
            var seen = Set<String>()
            func append(_ id: String) {
                let found = installed[id] != nil || NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
                guard found, seen.insert(id).inserted else { return }
                ids.append(id)
            }
            for id in recipe.bundleIDs { append(id) }
            for key in recipe.categoryKeys {
                let matches = (byCategory[key] ?? []).sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                for app in matches { append(app.bundleID) }
            }
            let color = palette.indices.contains(index) ? palette[index] : recipe.colorHex
            return Made(title: recipe.title, symbol: recipe.symbol, colorHex: color, bundleIDs: ids)
        }
    }
}
