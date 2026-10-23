import AppKit
import Foundation
import SwiftData
import SwiftUI

enum SkuffProduct {
    static let proID = "no.voq.skuff.pro"
    static let freeAppTabLimit = 5
    /// Tạm mở khóa Pro để thử. Đặt lại `false` trước khi phát hành.
    static let paywallDisabled = true
}

enum TabKind: String, Codable {
    case apps
    case folders
    case smartFilter
}

nonisolated enum FolderViewMode: String, Codable, CaseIterable, Identifiable {
    case grid
    case list
    var id: String { rawValue }
    var title: String { self == .grid ? "Grid" : "List" }
}

nonisolated enum FolderSortKey: String, Codable, CaseIterable, Identifiable {
    case name
    case dateModified
    case kind
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: "Name"
        case .dateModified: "Date modified"
        case .kind: "Kind"
        }
    }
}

nonisolated enum FileKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case documents
    case images
    case pdf
    case code
    case archives
    case folders
    var id: String { rawValue }
    var title: String {
        switch self {
        case .documents: "Documents"
        case .images: "Images"
        case .pdf: "PDF"
        case .code: "Code"
        case .archives: "Archives"
        case .folders: "Folders"
        }
    }
}

nonisolated struct FolderSource: Codable, Equatable {
    var path: String
    var bookmark: Data?
    var viewMode: FolderViewMode = .grid
    var sort: FolderSortKey = .name
    var sortAscending: Bool = true
    var showHidden: Bool = false
    var excludedNames: [String] = [".git", "node_modules", ".DS_Store"]
    var searchContent: Bool = true
    var typeFilter: [FileKind] = []

    enum CodingKeys: String, CodingKey {
        case path, bookmark, viewMode, sort, sortAscending, showHidden, excludedNames, searchContent, typeFilter
    }

    init(
        path: String,
        bookmark: Data? = nil,
        viewMode: FolderViewMode = .grid,
        sort: FolderSortKey = .name,
        sortAscending: Bool = true,
        showHidden: Bool = false,
        excludedNames: [String] = [".git", "node_modules", ".DS_Store"],
        searchContent: Bool = true,
        typeFilter: [FileKind] = []
    ) {
        self.path = path
        self.bookmark = bookmark
        self.viewMode = viewMode
        self.sort = sort
        self.sortAscending = sortAscending
        self.showHidden = showHidden
        self.excludedNames = excludedNames
        self.searchContent = searchContent
        self.typeFilter = typeFilter
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        bookmark = try container.decodeIfPresent(Data.self, forKey: .bookmark)
        viewMode = try container.decodeIfPresent(FolderViewMode.self, forKey: .viewMode) ?? .grid
        sort = try container.decodeIfPresent(FolderSortKey.self, forKey: .sort) ?? .name
        sortAscending = try container.decodeIfPresent(Bool.self, forKey: .sortAscending) ?? true
        showHidden = try container.decodeIfPresent(Bool.self, forKey: .showHidden) ?? false
        excludedNames = try container.decodeIfPresent([String].self, forKey: .excludedNames) ?? [".git", "node_modules", ".DS_Store"]
        searchContent = try container.decodeIfPresent(Bool.self, forKey: .searchContent) ?? true
        typeFilter = try container.decodeIfPresent([FileKind].self, forKey: .typeFilter) ?? []
    }
}

enum TabEditorMode {
    case new
    case edit(UUID)
}

func skuffItemCount(_ count: Int) -> String {
    count == 1 ? "1 item" : "\(count) items"
}

enum ProFeature {
    case folderTabs
    case contentSearch
    case imageIcons
    case customFonts

    func isUnlocked(in store: LibraryStore) -> Bool {
        store.pro.isPro
    }
}

enum TabIcon: Equatable {
    case emoji(String)
    case sfSymbol(String)
    case image(String)
}

extension TabIcon: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .emoji(let value):
            try container.encode("emoji", forKey: .type)
            try container.encode(value, forKey: .value)
        case .sfSymbol(let value):
            try container.encode("sfSymbol", forKey: .type)
            try container.encode(value, forKey: .value)
        case .image(let value):
            try container.encode("image", forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let value = try container.decode(String.self, forKey: .value)
        switch type {
        case "emoji": self = .emoji(value)
        case "sfSymbol": self = .sfSymbol(value)
        case "image": self = .image(value)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown tab icon type."
            )
        }
    }
}

nonisolated struct SmartFilter: Codable, Equatable {
    var fileTypes: [String] = []
    var extensions: [String] = []
    var finderTags: [String] = []
    var modifiedWithinDays: Int?
    var nameContains: String?
    var locations: [String] = []
    var sortKey: String?
}

enum ScreenEdge: String, Codable, CaseIterable, Identifiable {
    case left
    case right
    case top
    case bottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }

    /// Tabs run in a row. Left and right stack downward.
    var runsAlongX: Bool { self == .top || self == .bottom }
}

enum ThemePreset: String, Codable, CaseIterable, Identifiable {
    case pastel
    case manila
    case mono
    case ocean
    case forest
    case dusk
    case ink
    case ember
    case frost
    case berry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pastel: "Pastel"
        case .manila: "Manila"
        case .mono: "Mono"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .dusk: "Dusk"
        case .ink: "Ink"
        case .ember: "Ember"
        case .frost: "Frost"
        case .berry: "Berry"
        }
    }

    var isFree: Bool { self == .pastel }

    var palette: [String] {
        switch self {
        case .pastel:
            ["F6C6CE", "F8D7A8", "F6E7A8", "CFE6C4", "B9E0E2", "C9D5F6", "E4C6EA", "F6D5E4"]
        case .manila:
            ["F3E2B8", "E7D09A", "F7E8C4", "E2C98A", "F0D7A4", "DCC48A"]
        case .mono:
            ["F2F2F2", "E0E0E0", "CECECE", "BDBDBD", "D6D6D6", "E8E8E8"]
        case .ocean:
            ["C5E4F5", "A9D4EE", "B7E3E4", "9EC9E8", "D4E8F7", "8FB8D9", "C9E7F2", "A3D5C8"]
        case .forest:
            ["C8E0C0", "A8CFA0", "D5E8C8", "8FBF8A", "E4F0D4", "B7D4A8", "9CC9B0", "D0E4C4"]
        case .dusk:
            ["E4C4E0", "C9B6E8", "F0D0E4", "B9A8DC", "E8C8D8", "D4B8E0", "C6D0F0", "E0C4D4"]
        case .ink:
            ["2C333A", "3A424A", "243038", "4A545C", "1E2A32", "353E46", "2A343C", "414A52"]
        case .ember:
            ["F4B183", "E9896A", "F2C094", "D96B4F", "F6D3A8", "C75B4A", "E8A07A", "F0C4B0"]
        case .frost:
            ["D7E7F5", "C2D8EC", "E4EEF7", "AFC9E2", "F2F6FA", "9BB6D4", "C9DCEF", "B8CBDC"]
        case .berry:
            ["E8B7D0", "D49BBF", "F0C8DC", "C486B4", "E4A8C8", "B56A9E", "F3D4E4", "CFA0C2"]
        }
    }
}

enum StaggerPattern: String, CaseIterable, Codable, Identifiable {
    case none
    case stairUp
    case stairDown
    case alternate
    case wave
    case random
    case activeTall

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .stairUp: "Stair up"
        case .stairDown: "Stair down"
        case .alternate: "Alternate"
        case .wave: "Wave"
        case .random: "Random"
        case .activeTall: "Active tall"
        }
    }
}

func skuffStaggerOffset(
    index: Int,
    count: Int,
    pattern: StaggerPattern,
    amount: CGFloat,
    isActive: Bool,
    seed: Int = 7
) -> CGFloat {
    let t = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 0
    switch pattern {
    case .none: return 0
    case .stairUp: return amount * t
    case .stairDown: return amount * (1 - t)
    case .alternate: return index % 2 == 0 ? 0 : amount
    case .wave: return amount * (0.5 + 0.5 * sin(CGFloat(index) * 1.2))
    case .random:
        let hash = abs((index &* 2654435761 &+ seed) % 1000)
        return amount * CGFloat(hash) / 1000
    case .activeTall: return isActive ? amount : 0
    }
}

enum ShapeTemplate: String, Codable, CaseIterable, Identifiable {
    case standard
    case flat
    case folder
    case pill
    case stacked
    case stagger
    case wave
    case sawtooth
    case cascade
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .flat: "Flat"
        case .folder: "Folder"
        case .pill: "Pill"
        case .stacked: "Stacked"
        case .stagger: "Stagger"
        case .wave: "Wave"
        case .sawtooth: "Sawtooth"
        case .cascade: "Cascade"
        case .custom: "Custom"
        }
    }

    var isFree: Bool { self == .standard }

    var preset: EffectiveShape? {
        switch self {
        case .standard:
            EffectiveShape(slant: 8, cornerRadius: 8, tabWidth: 34, tabHeight: 86, overlap: 10)
        case .flat:
            EffectiveShape(slant: 0, cornerRadius: 2, tabWidth: 32, tabHeight: 72, overlap: 2)
        case .folder:
            EffectiveShape(slant: 12, cornerRadius: 4, tabWidth: 40, tabHeight: 96, overlap: 12)
        case .pill:
            EffectiveShape(slant: 0, cornerRadius: 16, tabWidth: 36, tabHeight: 80, overlap: 6)
        case .stacked:
            EffectiveShape(slant: 6, cornerRadius: 6, tabWidth: 28, tabHeight: 64, overlap: 20)
        case .stagger:
            EffectiveShape(slant: 8, cornerRadius: 8, tabWidth: 34, tabHeight: 86, overlap: 10, staggerPattern: .alternate, staggerAmount: 10)
        case .wave:
            EffectiveShape(slant: 8, cornerRadius: 12, tabWidth: 34, tabHeight: 86, overlap: 10, staggerPattern: .wave, staggerAmount: 14)
        case .sawtooth:
            EffectiveShape(slant: 8, cornerRadius: 4, tabWidth: 34, tabHeight: 86, overlap: 8, skew: -12, staggerPattern: .stairUp, staggerAmount: 16)
        case .cascade:
            EffectiveShape(slant: 8, cornerRadius: 8, tabWidth: 34, tabHeight: 86, overlap: 10, skew: 8, staggerPattern: .stairDown, staggerAmount: 18)
        case .custom:
            nil
        }
    }
}

enum FullScreenBehavior: String, Codable, CaseIterable, Identifiable {
    case alwaysShow
    case collapseToHandle
    case hideCompletely

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alwaysShow: "Always show"
        case .collapseToHandle: "Collapse to edge handle"
        case .hideCompletely: "Hide completely"
        }
    }
}

enum FullScreenExclusionMode: String, Codable, CaseIterable, Identifiable {
    case alwaysShow
    case hide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alwaysShow: "Always show"
        case .hide: "Hide"
        }
    }
}

struct FullScreenAppRule: Codable, Equatable, Identifiable {
    var bundleID: String
    var mode: FullScreenExclusionMode
    var id: String { bundleID }
}

enum SheetMotion: String, Codable, CaseIterable, Identifiable {
    case slide
    case fade

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slide: "Slide in"
        case .fade: "Fade in"
        }
    }

    var symbol: String {
        switch self {
        case .slide: "rectangle.portrait.and.arrow.right"
        case .fade: "circle.lefthalf.filled"
        }
    }
}

enum TabFinish: String, Codable, CaseIterable, Identifiable {
    case flat
    case gradient
    case liquid
    case glass
    case neon
    case sticker
    case aurora

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flat: "Flat"
        case .gradient: "Gradient"
        case .liquid: "Liquid"
        case .glass: "Glass"
        case .neon: "Neon"
        case .sticker: "Sticker"
        case .aurora: "Aurora"
        }
    }

    var symbol: String {
        switch self {
        case .flat: "square.fill"
        case .gradient: "circle.lefthalf.filled"
        case .liquid: "drop.halffull"
        case .glass: "rectangle.on.rectangle.angled"
        case .neon: "sun.max.fill"
        case .sticker: "diamond.fill"
        case .aurora: "sparkles"
        }
    }

    var usesThemeColor: Bool { self != .liquid }
}

struct SkuffSettings: Equatable {
    var slant: Double = 8
    var cornerRadius: Double = 8
    var tabWidth: Double = 34
    var tabHeight: Double = 86
    var overlap: Double = 10
    var edge: ScreenEdge = .right
    var fullScreenBehavior: FullScreenBehavior = .collapseToHandle
    var respectMenuBarAndDock: Bool = true
    var fullScreenExclusions: [FullScreenAppRule] = []
    var toggleHotkeyEnabled: Bool = true
    var toggleHotkeyKeyCode: Int = 49
    var toggleHotkeyCarbonModifiers: Int = 2048
    var theme: ThemePreset = .pastel
    var shapeTemplate: ShapeTemplate = .standard
    var sheetMotion: SheetMotion = .slide
    var tabFinish: TabFinish = .flat
    var skew: Double = 0
    var staggerPattern: StaggerPattern = .none
    var staggerAmount: Double = 0
    var tilt: Double = 0
    var staggerSeed: Int = 7
    var joinRadius: Double = 10
    var connectedTab: Bool = true
    var tabShadow: Double = 0.5
    var paperEdge: Bool = true
    var globalFontName: String?
    var globalFontSize: Double = 13
    var globalFontWeight: Double = 0.4
    var shortcutsEnabled: Bool = true
    var folderViewMode: FolderViewMode = .grid
    var folderSort: FolderSortKey = .name
    var folderSortAscending: Bool = true
    var folderShowHidden: Bool = false
    var folderExcludedNames: [String] = [".git", "node_modules", ".DS_Store"]
    var folderThumbnails: Bool = true

    mutating func clamp() {
        slant = min(12, max(0, slant))
        cornerRadius = min(16, max(0, cornerRadius))
        tabWidth = min(48, max(24, tabWidth))
        tabHeight = min(140, max(40, tabHeight))
        overlap = min(24, max(0, overlap))
        skew = min(30, max(-30, skew))
        staggerAmount = min(24, max(0, staggerAmount))
        tilt = min(6, max(-6, tilt))
        joinRadius = min(20, max(0, joinRadius))
        tabShadow = min(1, max(0, tabShadow))
        globalFontSize = min(22, max(9, globalFontSize))
        globalFontWeight = min(1, max(0, globalFontWeight))
    }

    func effectiveShape(isPro: Bool) -> EffectiveShape {
        if isPro {
            return EffectiveShape(
                slant: CGFloat(slant),
                cornerRadius: CGFloat(cornerRadius),
                tabWidth: CGFloat(tabWidth),
                tabHeight: CGFloat(tabHeight),
                overlap: CGFloat(overlap),
                skew: CGFloat(skew),
                staggerPattern: staggerPattern,
                staggerAmount: CGFloat(staggerAmount),
                tilt: CGFloat(tilt),
                staggerSeed: staggerSeed
            )
        }
        let defaults = SkuffSettings()
        return EffectiveShape(
            slant: CGFloat(defaults.slant),
            cornerRadius: CGFloat(defaults.cornerRadius),
            tabWidth: CGFloat(defaults.tabWidth),
            tabHeight: CGFloat(defaults.tabHeight),
            overlap: CGFloat(defaults.overlap)
        )
    }
}

struct EffectiveShape: Equatable {
    var slant: CGFloat
    var cornerRadius: CGFloat
    var tabWidth: CGFloat
    var tabHeight: CGFloat
    var overlap: CGFloat
    var skew: CGFloat = 0
    var staggerPattern: StaggerPattern = .none
    var staggerAmount: CGFloat = 0
    var tilt: CGFloat = 0
    var staggerSeed: Int = 7
}

extension SkuffSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case slant, cornerRadius, tabWidth, tabHeight, overlap, edge
        case fullScreenBehavior, respectMenuBarAndDock, fullScreenExclusions
        case toggleHotkeyEnabled, toggleHotkeyKeyCode, toggleHotkeyCarbonModifiers
        case theme, shapeTemplate, sheetMotion, tabFinish
        case skew, staggerPattern, staggerAmount, tilt, staggerSeed
        case joinRadius, connectedTab, tabShadow, paperEdge
        case globalFontName, globalFontSize, globalFontWeight, shortcutsEnabled
        case folderViewMode, folderSort, folderSortAscending, folderShowHidden, folderExcludedNames, folderThumbnails
    }

    private enum LegacyKeys: String, CodingKey {
        case hideWhenFullscreen
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slant = try container.decodeIfPresent(Double.self, forKey: .slant) ?? 8
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 8
        tabWidth = try container.decodeIfPresent(Double.self, forKey: .tabWidth) ?? 34
        tabHeight = try container.decodeIfPresent(Double.self, forKey: .tabHeight) ?? 86
        overlap = try container.decodeIfPresent(Double.self, forKey: .overlap) ?? 10
        edge = try container.decodeIfPresent(ScreenEdge.self, forKey: .edge) ?? .right
        if let behavior = try container.decodeIfPresent(FullScreenBehavior.self, forKey: .fullScreenBehavior) {
            fullScreenBehavior = behavior
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            if let hide = try legacy.decodeIfPresent(Bool.self, forKey: .hideWhenFullscreen) {
                fullScreenBehavior = hide ? .collapseToHandle : .alwaysShow
            } else {
                fullScreenBehavior = .collapseToHandle
            }
        }
        respectMenuBarAndDock = try container.decodeIfPresent(Bool.self, forKey: .respectMenuBarAndDock) ?? true
        fullScreenExclusions = try container.decodeIfPresent([FullScreenAppRule].self, forKey: .fullScreenExclusions) ?? []
        toggleHotkeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .toggleHotkeyEnabled) ?? true
        toggleHotkeyKeyCode = try container.decodeIfPresent(Int.self, forKey: .toggleHotkeyKeyCode) ?? 49
        toggleHotkeyCarbonModifiers = try container.decodeIfPresent(Int.self, forKey: .toggleHotkeyCarbonModifiers) ?? 2048
        theme = try container.decodeIfPresent(ThemePreset.self, forKey: .theme) ?? .pastel
        shapeTemplate = try container.decodeIfPresent(ShapeTemplate.self, forKey: .shapeTemplate) ?? .standard
        sheetMotion = try container.decodeIfPresent(SheetMotion.self, forKey: .sheetMotion) ?? .slide
        tabFinish = try container.decodeIfPresent(TabFinish.self, forKey: .tabFinish) ?? .flat
        skew = try container.decodeIfPresent(Double.self, forKey: .skew) ?? 0
        staggerPattern = try container.decodeIfPresent(StaggerPattern.self, forKey: .staggerPattern) ?? .none
        staggerAmount = try container.decodeIfPresent(Double.self, forKey: .staggerAmount) ?? 0
        tilt = try container.decodeIfPresent(Double.self, forKey: .tilt) ?? 0
        staggerSeed = try container.decodeIfPresent(Int.self, forKey: .staggerSeed) ?? 7
        joinRadius = try container.decodeIfPresent(Double.self, forKey: .joinRadius) ?? 10
        connectedTab = try container.decodeIfPresent(Bool.self, forKey: .connectedTab) ?? true
        tabShadow = try container.decodeIfPresent(Double.self, forKey: .tabShadow) ?? 0.5
        paperEdge = try container.decodeIfPresent(Bool.self, forKey: .paperEdge) ?? true
        globalFontName = try container.decodeIfPresent(String.self, forKey: .globalFontName)
        globalFontSize = try container.decodeIfPresent(Double.self, forKey: .globalFontSize) ?? 13
        globalFontWeight = try container.decodeIfPresent(Double.self, forKey: .globalFontWeight) ?? 0.4
        shortcutsEnabled = try container.decodeIfPresent(Bool.self, forKey: .shortcutsEnabled) ?? true
        folderViewMode = try container.decodeIfPresent(FolderViewMode.self, forKey: .folderViewMode) ?? .grid
        folderSort = try container.decodeIfPresent(FolderSortKey.self, forKey: .folderSort) ?? .name
        folderSortAscending = try container.decodeIfPresent(Bool.self, forKey: .folderSortAscending) ?? true
        folderShowHidden = try container.decodeIfPresent(Bool.self, forKey: .folderShowHidden) ?? false
        folderExcludedNames = try container.decodeIfPresent([String].self, forKey: .folderExcludedNames) ?? [".git", "node_modules", ".DS_Store"]
        folderThumbnails = try container.decodeIfPresent(Bool.self, forKey: .folderThumbnails) ?? true
        clamp()
    }
}

struct ScreenAnchor: Codable, Equatable {
    var offset: Double = 0
}

struct SkuffColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var hex: String

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    var luminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    var textColor: Color {
        luminance > 0.55 ? Color.black.opacity(0.88) : Color.white
    }

    func dimmed(_ factor: Double = 0.92) -> SkuffColor {
        SkuffColor(color: Color(red: red * factor, green: green * factor, blue: blue * factor))
    }

    init(hex raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        Scanner(string: text).scanHexInt64(&value)
        if text.count >= 6 {
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
        } else {
            red = 0.965
            green = 0.776
            blue = 0.808
        }
        hex = String(format: "%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    init(color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .white
        red = Double(resolved.redComponent)
        green = Double(resolved.greenComponent)
        blue = Double(resolved.blueComponent)
        hex = String(format: "%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}

struct FolderTab: Identifiable, Equatable {
    var id: UUID
    var kind: TabKind
    var title: String
    var icon: TabIcon?
    var colorHex: String
    var fontName: String?
    var fontSize: Double?
    var fontWeight: Double?
    var appBundleIDs: [String]
    var pinnedAppBundleIDs: [String] = []
    /// Per-Mac bookmark bytes. Kept on the value type and omitted from JSON
    /// because a security-scoped bookmark cannot be used on another Mac.
    var folderBookmarks: [Data] = []
    var folderRelativePaths: [String]
    var folderSource: FolderSource? = nil
    var filter: SmartFilter?
    var isPinned: Bool
    var sortOrder: Int
    var updatedAt: Date
    var categoryKey: String?
}

extension FolderTab: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, title, icon, colorHex, fontName, fontSize, fontWeight
        case appBundleIDs, folderRelativePaths, folderSource, filter, isPinned, sortOrder, updatedAt, categoryKey
    }
}

struct SkuffDocument: Codable {
    var version: Int
    var tabs: [FolderTab]
    var settings: SkuffSettings
    var images: [String: String]
}

struct InstalledApp: Identifiable, Equatable {
    var bundleID: String
    var name: String
    var url: URL
    var category: String
    var id: String { bundleID }
}

@Model
final class FolderTabRecord {
    var id: UUID = UUID()
    var kindRaw: String = TabKind.apps.rawValue
    var title: String = "New Tab"
    var iconEmoji: String?
    var iconSymbol: String?
    var iconImageFilename: String?
    var colorHex: String = "F6C6CE"
    var fontName: String?
    var fontSize: Double?
    var fontWeight: Double?
    var appBundleIDs: [String] = []
    var pinnedAppBundleIDs: [String] = []
    var folderRelativePaths: [String] = []
    var folderSourceJSON: String?
    var filterJSON: String?
    var isPinned: Bool = false
    var sortOrder: Int = 0
    var updatedAt: Date = Date()
    var categoryKey: String?

    init(
        id: UUID = UUID(),
        kind: TabKind = .apps,
        title: String = "New Tab",
        colorHex: String = "F6C6CE",
        sortOrder: Int = 0,
        categoryKey: String? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.title = title
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.categoryKey = categoryKey
        self.updatedAt = Date()
        self.appBundleIDs = []
        self.pinnedAppBundleIDs = []
        self.folderRelativePaths = []
        self.isPinned = false
    }

    var kind: TabKind {
        get { TabKind(rawValue: kindRaw) ?? .apps }
        set { kindRaw = newValue.rawValue }
    }

    var icon: TabIcon? {
        get {
            if let iconEmoji, !iconEmoji.isEmpty { return .emoji(iconEmoji) }
            if let iconSymbol, !iconSymbol.isEmpty { return .sfSymbol(iconSymbol) }
            if let iconImageFilename, !iconImageFilename.isEmpty { return .image(iconImageFilename) }
            return nil
        }
        set {
            iconEmoji = nil
            iconSymbol = nil
            iconImageFilename = nil
            switch newValue {
            case .emoji(let value): iconEmoji = value
            case .sfSymbol(let value): iconSymbol = value
            case .image(let value): iconImageFilename = value
            case nil: break
            }
        }
    }

    var folderSource: FolderSource? {
        get {
            guard let folderSourceJSON, let data = folderSourceJSON.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(FolderSource.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                folderSourceJSON = nil
                return
            }
            folderSourceJSON = String(data: data, encoding: .utf8)
        }
    }

    var filter: SmartFilter? {
        get {
            guard let filterJSON, let data = filterJSON.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(SmartFilter.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                filterJSON = nil
                return
            }
            filterJSON = String(data: data, encoding: .utf8)
        }
    }

    func snapshot() -> FolderTab {
        FolderTab(
            id: id,
            kind: kind,
            title: title,
            icon: icon,
            colorHex: colorHex,
            fontName: fontName,
            fontSize: fontSize,
            fontWeight: fontWeight,
            appBundleIDs: appBundleIDs,
            pinnedAppBundleIDs: pinnedAppBundleIDs,
            folderBookmarks: [],
            folderRelativePaths: folderRelativePaths,
            folderSource: folderSource,
            filter: filter,
            isPinned: isPinned,
            sortOrder: sortOrder,
            updatedAt: updatedAt,
            categoryKey: categoryKey
        )
    }
}

func skuffNSFontWeight(_ value: Double) -> NSFont.Weight {
    switch value {
    case ..<0.15: .ultraLight
    case ..<0.30: .light
    case ..<0.45: .regular
    case ..<0.60: .medium
    case ..<0.75: .semibold
    case ..<0.90: .bold
    default: .heavy
    }
}

func skuffFontWeight(_ value: Double) -> Font.Weight {
    switch value {
    case ..<0.15: .ultraLight
    case ..<0.30: .light
    case ..<0.45: .regular
    case ..<0.60: .medium
    case ..<0.75: .semibold
    case ..<0.90: .bold
    default: .heavy
    }
}

func skuffFontWeightName(_ value: Double) -> String {
    switch value {
    case ..<0.15: "Ultra Light"
    case ..<0.30: "Light"
    case ..<0.45: "Regular"
    case ..<0.60: "Medium"
    case ..<0.75: "Semibold"
    case ..<0.90: "Bold"
    default: "Heavy"
    }
}
