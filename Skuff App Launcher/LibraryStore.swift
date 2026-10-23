import AppKit
import os
import Combine
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LibraryStore: ObservableObject {
    let container: ModelContainer
    let pro = ProStore()
    let library = AppLibrary()

    @Published private(set) var tabs: [FolderTabRecord] = []
    @Published var apps: [String: InstalledApp] = [:]
    @Published var runningBundleIDs: Set<String> = []
    @Published var settings: SkuffSettings
    @Published var screenAnchors: [String: ScreenAnchor]
    @Published var names: [String: String]
    @Published var openTabID: UUID?
    @Published var openScreenID: String?
    @Published var failedHotkeys: [Int] = []
    @Published var ioMessage: String? = nil
    @Published var screenGeneration = 0
    @Published var settingsEpoch = 0
    @Published var openBump: CGRect = .zero
    @Published var undoBanner: UndoBanner?
    @Published var tabsManuallyHidden = false
    @Published var collapsedScreens: Set<String> = []
    @Published var failedToggleHotkey = false
    @Published var recordingToggleHotkey = false
    /// True while a folder is open, so its search field can take typing right away.
    /// The panel is non-activating: this takes key focus without bringing Skuff forward.
    @Published private(set) var folderWantsKeyboard = false
    /// Bumped when the folder panel becomes key, so the search field can take focus.
    @Published private(set) var searchFocusRequest = 0

    var onChange: (() -> Void)?
    var presentTogglePanel: (() -> Void)?
    var presentSettings: (() -> Void)?
    /// Set by `PanelController`; the open folder reports spare (+) or missing (−) height.
    var onSheetSlack: ((UUID, CGFloat) -> Void)?
    var context: ModelContext { container.mainContext }

    private var iconCache: [String: NSImage] = [:]
    private var bag = Set<AnyCancellable>()
    private var hotkeyToken: NSObjectProtocol?
    private var toggleToken: NSObjectProtocol?
    private var recordMonitor: Any?
    private var launchToken: NSObjectProtocol?
    private var terminateToken: NSObjectProtocol?
    private var organizing = false
    private var undoTask: Task<Void, Never>?

    init() {
        do {
            container = try ModelContainer(
                for: FolderTabRecord.self,
                configurations: ModelConfiguration(cloudKitDatabase: .none)
            )
        } catch {
            do {
                container = try ModelContainer(
                    for: FolderTabRecord.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
                ioMessage = "Skuff couldn't open its database and is using temporary storage."
            } catch {
                fatalError("Unable to create a Skuff store: \(error)")
            }
        }
        settings = SettingsStore.load()
        screenAnchors = SettingsStore.loadAnchors()
        names = UserDefaults.standard.dictionary(forKey: SettingsStore.namesKey) as? [String: String] ?? [:]
        reload()
        pro.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &bag)
        pro.$isPro.dropFirst().sink { [weak self] _ in
            self?.onChange?()
        }.store(in: &bag)
    }

    func bootstrap() {
        refreshRunning()
        let workspace = NSWorkspace.shared.notificationCenter
        launchToken = workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            guard let store = self else { return }
            Task { @MainActor in store.refreshRunning() }
        }
        terminateToken = workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            guard let store = self else { return }
            Task { @MainActor in store.refreshRunning() }
        }
        hotkeyToken = NotificationCenter.default.addObserver(forName: .skuffHotkey, object: nil, queue: .main) { [weak self] note in
            let index = note.userInfo?["index"] as? Int ?? -1
            guard let store = self else { return }
            Task { @MainActor in store.openHotkey(index) }
        }
        toggleToken = NotificationCenter.default.addObserver(forName: .skuffTogglePanel, object: nil, queue: .main) { [weak self] _ in
            guard let store = self else { return }
            Task { @MainActor in store.requestTogglePanel() }
        }
        refreshHotkeys()
        library.onUpdate = { [weak self] found in
            self?.applyFoundApps(found)
        }
        library.start()
        pro.start()
    }

    func reload() {
        let descriptor = FetchDescriptor<FolderTabRecord>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.title)]
        )
        tabs = (try? context.fetch(descriptor)) ?? []
    }

    func orderedTabs() -> [FolderTabRecord] {
        tabs.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder { return lhs.title < rhs.title }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    func isBeyondFreeLimit(_ tab: FolderTabRecord) -> Bool {
        if pro.isPro && tab.kind == .apps { return false }
        if tab.kind != .apps { return !pro.isPro }
        let appTabs = orderedTabs().filter { $0.kind == .apps }
        guard let index = appTabs.firstIndex(where: { $0.id == tab.id }) else { return true }
        return index >= SkuffProduct.freeAppTabLimit
    }

    func refreshRunning() {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if ids != runningBundleIDs {
            runningBundleIDs = ids
        }
    }

    func tabContainsRunningApp(_ tab: FolderTabRecord) -> Bool {
        tab.appBundleIDs.contains { runningBundleIDs.contains($0) }
    }

    func displayName(for bundleID: String) -> String {
        if let name = apps[bundleID]?.name { return name }
        if let name = names[bundleID] { return name }
        return bundleID
    }

    func resolvedURL(for bundleID: String) -> URL? {
        if let url = apps[bundleID]?.url, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    func isInstalled(_ bundleID: String) -> Bool {
        resolvedURL(for: bundleID) != nil
    }

    func icon(for bundleID: String) -> NSImage {
        if let cached = iconCache[bundleID] { return cached }
        let image: NSImage
        if let url = resolvedURL(for: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        iconCache[bundleID] = image
        return image
    }

    func font(for tab: FolderTabRecord) -> Font {
        let size = pro.isPro ? (tab.fontSize ?? settings.globalFontSize) : 13
        let weight = skuffFontWeight(pro.isPro ? (tab.fontWeight ?? settings.globalFontWeight) : 0.4)
        if pro.isPro, let name = tab.fontName ?? settings.globalFontName, !name.isEmpty {
            return Font.custom(name, size: size).weight(weight)
        }
        return Font.system(size: size, weight: weight)
    }

    func toggleTab(_ id: UUID, on screenID: String) {
        #if DEBUG
        Logger.input.info("toggleTab \(self.tabs.first { $0.id == id }?.title ?? "?", privacy: .public) wasOpen=\(self.openTabID == id)")
        #endif
        refreshRunning()
        if openTabID == id {
            openTabID = nil
            openScreenID = nil
            folderWantsKeyboard = false
        } else {
            openTabID = id
            openScreenID = screenID
            folderWantsKeyboard = true
        }
        onChange?()
    }

    func closeFolder() {
        guard openTabID != nil else { return }
        openTabID = nil
        openScreenID = nil
        folderWantsKeyboard = false
        onChange?()
    }

    func reportSheetSlack(_ slack: CGFloat, for id: UUID) {
        onSheetSlack?(id, slack)
    }

    func requestSearchFocus() {
        searchFocusRequest += 1
    }

    func openHotkey(_ index: Int) {
        let ordered = orderedTabs()
        guard ordered.indices.contains(index) else { return }
        let screen = screenUnderMouse()
        let tab = ordered[index]
        if openTabID == tab.id {
            closeFolder()
        } else {
            openTabID = tab.id
            openScreenID = screen
            folderWantsKeyboard = true
            refreshRunning()
            onChange?()
        }
    }

    func addTab() {
        let appTabs = orderedTabs().filter { $0.kind == .apps }
        if !pro.isPro && appTabs.count >= SkuffProduct.freeAppTabLimit + 1 {
            if let locked = appTabs.dropFirst(SkuffProduct.freeAppTabLimit).first {
                openTabID = locked.id
                openScreenID = openScreenID ?? screenUnderMouse()
                onChange?()
            }
            return
        }
        TabEditorPresenter.shared.presentNew(store: self)
    }

    func commitNewTab(from draft: TabEditorDraft) {
        let record = FolderTabRecord(
            title: draft.trimmedTitle,
            colorHex: draft.colorHex,
            sortOrder: (tabs.map(\.sortOrder).max() ?? -1) + 1
        )
        record.icon = draft.icon
        record.folderSource = draft.folderSource
        if draft.folderSource != nil {
            record.kind = .folders
        }
        record.isPinned = draft.isPinned
        record.appBundleIDs = draft.appBundleIDs
        if draft.customFont, pro.isPro {
            record.fontName = draft.fontName
            record.fontSize = draft.fontSize
            record.fontWeight = draft.fontWeight
        }
        context.insert(record)
        save()
        RecentIcons.remember(draft.icon)
        openTabID = record.id
        openScreenID = screenUnderMouse()
        onChange?()
    }

    func editTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        TabEditorPresenter.shared.presentEdit(store: self, tab: tab)
    }

    func setFolderSource(_ id: UUID, _ source: FolderSource?) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.folderSource = source
        if source != nil { tab.kind = .folders } else if tab.kind == .folders { tab.kind = .apps }
        tab.updatedAt = Date()
        save()
    }

    func setFolderSource(_ id: UUID, mutate: (inout FolderSource) -> Void) {
        guard let tab = tabs.first(where: { $0.id == id }), var source = tab.folderSource else { return }
        mutate(&source)
        tab.folderSource = source
        tab.updatedAt = Date()
        save()
    }

    func chooseFolder(for id: UUID) {
        guard ProFeature.folderTabs.isUnlocked(in: self) else {
            pro.lastError = "Folder tabs and content search are Pro features"
            return
        }
        guard let url = FolderAccess.chooseFolder() else { return }
        applyFolder(url, to: id, confirm: false)
    }

    /// Re-asks for access to the tab's own folder, keeping its view settings.
    func grantFolderAccess(for id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }), let source = tab.folderSource else { return }
        let current = URL(fileURLWithPath: (source.path as NSString).expandingTildeInPath)
        let start = FolderAccess.exists(current) ? current : current.deletingLastPathComponent()
        guard let url = FolderAccess.chooseFolder(startingAt: start, prompt: "Grant Access") else { return }
        let bookmark = FolderAccess.bookmark(for: url)
        setFolderSource(id) {
            $0.path = url.path
            $0.bookmark = bookmark
        }
    }

    /// Stores a refreshed bookmark without a UI refresh; the folder is already showing.
    func refreshFolderBookmark(_ id: UUID, _ bookmark: Data) {
        guard let tab = tabs.first(where: { $0.id == id }), var source = tab.folderSource, source.bookmark != bookmark else { return }
        source.bookmark = bookmark
        tab.folderSource = source
        try? context.save()
    }

    func promptFolderUpgrade() {
        let alert = NSAlert()
        alert.messageText = "Folder tabs and content search are Pro features"
        alert.addButton(withTitle: pro.upgradeLabel)
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await pro.purchase() }
        }
    }

    func applyFolder(_ url: URL, to id: UUID?, confirm: Bool) {
        guard ProFeature.folderTabs.isUnlocked(in: self) else {
            promptFolderUpgrade()
            return
        }
        if let id, let tab = tabs.first(where: { $0.id == id }), tab.folderSource != nil, confirm {
            let alert = NSAlert()
            alert.messageText = "Replace this tab’s folder?"
            alert.informativeText = "The current folder source will be replaced."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let source = FolderSource(
            path: url.path,
            bookmark: FolderAccess.bookmark(for: url),
            viewMode: settings.folderViewMode,
            sort: settings.folderSort,
            sortAscending: settings.folderSortAscending,
            showHidden: settings.folderShowHidden,
            excludedNames: settings.folderExcludedNames
        )
        if let id {
            setFolderSource(id, source)
            if let tab = tabs.first(where: { $0.id == id }), tab.title == "New Tab" || tab.title == "Untitled" {
                rename(id, to: url.lastPathComponent)
            }
        } else {
            let record = FolderTabRecord(
                kind: .folders,
                title: url.lastPathComponent,
                colorHex: (pro.isPro ? settings.theme : .pastel).palette[tabs.count % max((pro.isPro ? settings.theme : .pastel).palette.count, 1)],
                sortOrder: (tabs.map(\.sortOrder).max() ?? -1) + 1
            )
            record.icon = .sfSymbol("folder")
            record.folderSource = source
            context.insert(record)
            save()
            openTabID = record.id
            openScreenID = screenUnderMouse()
            onChange?()
        }
    }

    func toggleFavorite(_ bundleID: String, in id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        guard tab.appBundleIDs.contains(bundleID) else { return }
        if let index = tab.pinnedAppBundleIDs.firstIndex(of: bundleID) {
            tab.pinnedAppBundleIDs.remove(at: index)
        } else {
            tab.pinnedAppBundleIDs.insert(bundleID, at: 0)
        }
        tab.updatedAt = Date()
        save()
    }

    func requestDeleteTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        if tab.folderSource != nil || tab.appBundleIDs.count > 3 {
            let alert = NSAlert()
            alert.messageText = "Delete “\(tab.title)”?"
            if tab.folderSource != nil {
                alert.informativeText = "This tab has a folder source. The folder itself is not deleted."
            } else {
                alert.informativeText = "This tab has \(tab.appBundleIDs.count) apps."
            }
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        snapshotThen("Tab deleted.") {
            deleteTab(id)
        }
    }

    func deleteTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        let filename = tab.iconImageFilename
        if openTabID == id { closeFolder() }
        context.delete(tab)
        save()
        if let filename, !tabs.contains(where: { $0.iconImageFilename == filename }) {
            IconStore.delete(filename)
        }
    }

    func replaceApps(_ id: UUID, with bundleIDs: [String]) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        var unique: [String] = []
        var seen = Set<String>()
        for item in bundleIDs where seen.insert(item).inserted {
            unique.append(item)
        }
        tab.appBundleIDs = unique
        tab.pinnedAppBundleIDs.removeAll { !unique.contains($0) }
        tab.updatedAt = Date()
        save()
    }

    func confirmRestoreDefaultTabs() {
        let alert = NSAlert()
        alert.messageText = "Restore default tabs?"
        alert.informativeText = "Replaces every tab with Office, Utilities, Video, Dev, Design, and Photography. Appearance settings stay as they are."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        snapshotThen("Default tabs restored.") {
            replaceAllTabsWithDefaults()
        }
    }

    func confirmResetAppearance() {
        let alert = NSAlert()
        alert.messageText = "Reset appearance?"
        alert.informativeText = "Restores Layout, Theme, Shape, and Font to their original values. Tabs and their apps stay as they are."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        snapshotThen("Appearance reset.") {
            var next = SkuffSettings()
            next.folderViewMode = settings.folderViewMode
            next.folderSort = settings.folderSort
            next.folderSortAscending = settings.folderSortAscending
            next.folderShowHidden = settings.folderShowHidden
            next.folderExcludedNames = settings.folderExcludedNames
            next.folderThumbnails = settings.folderThumbnails
            next.shortcutsEnabled = settings.shortcutsEnabled
            next.fullScreenBehavior = settings.fullScreenBehavior
            next.respectMenuBarAndDock = settings.respectMenuBarAndDock
            next.fullScreenExclusions = settings.fullScreenExclusions
            next.toggleHotkeyEnabled = settings.toggleHotkeyEnabled
            next.toggleHotkeyKeyCode = settings.toggleHotkeyKeyCode
            next.toggleHotkeyCarbonModifiers = settings.toggleHotkeyCarbonModifiers
            next.edge = settings.edge
            replaceSettings(next)
        }
    }

    func confirmResetEverything() {
        let alert = NSAlert()
        alert.messageText = "Reset everything?"
        alert.informativeText = "Restores default tabs (Office, Utilities, Video, Dev, Design, Photography) and resets Layout, Theme, Shape, Font, and all other settings."
        alert.addButton(withTitle: "Reset Everything")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        snapshotThen("Everything reset.") {
            replaceSettings(SkuffSettings())
            replaceAllTabsWithDefaults()
        }
    }

    func undoLastBackup() {
        guard let data = ConfigBackup.latestData() else { return }
        do {
            try ConfigTransfer.importDocument(data, into: self)
            undoBanner = nil
            ioMessage = "Restored."
        } catch {
            ioMessage = error.localizedDescription
        }
    }

    private func snapshotThen(_ message: String, _ body: () -> Void) {
        ConfigBackup.save(tabs: orderedTabs(), settings: settings)
        body()
        showUndo(message)
    }

    /// Short notice in the strip's banner, for actions that would otherwise fail silently.
    func flash(_ message: String) {
        showBanner(message, canUndo: false, seconds: 4)
    }

    private func showUndo(_ message: String) {
        showBanner(message, canUndo: true, seconds: 8)
    }

    private func showBanner(_ message: String, canUndo: Bool, seconds: UInt64) {
        let token = UUID()
        undoBanner = UndoBanner(message: message, token: token, canUndo: canUndo)
        undoTask?.cancel()
        undoTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            if undoBanner?.token == token {
                undoBanner = nil
            }
        }
    }

    private func replaceAllTabsWithDefaults() {
        closeFolder()
        for tab in tabs {
            context.delete(tab)
        }
        seedDefaultTabs()
    }

    private func seedDefaultTabs() {
        let palette = (pro.isPro ? settings.theme : .pastel).palette
        let made = DefaultTabs.make(installed: apps, palette: palette)
        for (index, item) in made.enumerated() {
            let record = FolderTabRecord(
                title: item.title,
                colorHex: item.colorHex,
                sortOrder: index
            )
            record.icon = .sfSymbol(item.symbol)
            record.appBundleIDs = item.bundleIDs
            context.insert(record)
        }
        save()
    }

    func togglePin(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.isPinned.toggle()
        tab.updatedAt = Date()
        save()
    }

    func rename(_ id: UUID, to title: String) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        tab.title = trimmed.isEmpty ? "Untitled" : trimmed
        tab.updatedAt = Date()
        save()
    }

    func setColor(_ id: UUID, _ color: Color) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.colorHex = SkuffColor(color: color).hex
        tab.updatedAt = Date()
        save()
    }

    func setEmoji(_ id: UUID, _ value: String) {
        let trimmed = String(value.prefix(8))
        setIcon(id, trimmed.isEmpty ? nil : .emoji(trimmed))
    }

    func setSymbol(_ id: UUID, _ name: String) {
        setIcon(id, .sfSymbol(name))
    }

    func setIcon(_ id: UUID, _ icon: TabIcon?) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        let previous = tab.iconImageFilename
        tab.icon = icon
        tab.updatedAt = Date()
        save()
        if let previous, previous != tab.iconImageFilename, !tabs.contains(where: { $0.iconImageFilename == previous }) {
            IconStore.delete(previous)
        }
    }

    func setFontOverride(_ id: UUID, enabled: Bool) {
        guard pro.isPro, let tab = tabs.first(where: { $0.id == id }) else { return }
        if enabled {
            tab.fontName = settings.globalFontName
            tab.fontSize = settings.globalFontSize
            tab.fontWeight = settings.globalFontWeight
        } else {
            tab.fontName = nil
            tab.fontSize = nil
            tab.fontWeight = nil
        }
        tab.updatedAt = Date()
        save()
    }

    func setTabFont(_ id: UUID, name: String?, size: Double, weight: Double) {
        guard pro.isPro, let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.fontName = name
        tab.fontSize = size
        tab.fontWeight = weight
        tab.updatedAt = Date()
        save()
    }

    func removeApp(_ bundleID: String, from id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.appBundleIDs.removeAll { $0 == bundleID }
        tab.pinnedAppBundleIDs.removeAll { $0 == bundleID }
        tab.updatedAt = Date()
        save()
    }

    func acceptDrop(_ providers: [NSItemProvider], onto id: UUID?) {
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            provider.loadObject(ofClass: NSURL.self) { [weak self] object, _ in
                guard let url = object as? URL else { return }
                guard let store = self else { return }
                let destination = id
                Task { @MainActor in
                    store.ingestDroppedURL(url, onto: destination)
                }
            }
        }
    }

    func acceptDropIntoDraft(_ providers: [NSItemProvider], draft: TabEditorDraft) {
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            provider.loadObject(ofClass: NSURL.self) { [weak self] object, _ in
                guard let url = object as? URL, url.pathExtension.lowercased() == "app" else { return }
                guard let store = self, let bundleID = AppInspector.bundleID(of: url) else { return }
                Task { @MainActor in
                    let name = AppInspector.displayName(of: url)
                    if store.apps[bundleID] == nil {
                        store.apps[bundleID] = InstalledApp(
                            bundleID: bundleID,
                            name: name,
                            url: url,
                            category: AppInspector.category(of: url)
                        )
                    }
                    if !draft.appBundleIDs.contains(bundleID) {
                        draft.appBundleIDs.append(bundleID)
                    }
                }
            }
        }
    }

    func ingestDroppedURL(_ url: URL, onto id: UUID?) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if url.pathExtension.lowercased() == "app" {
            if let id { addApp(at: url, to: id) }
            return
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            applyFolder(url, to: id, confirm: id != nil)
        } else if let id {
            addApp(at: url, to: id)
        }
    }

    func addApp(at url: URL, to id: UUID) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard url.pathExtension.lowercased() == "app" else {
            flash("Only apps can be added to this tab.")
            return
        }
        guard let bundleID = AppInspector.bundleID(of: url) else {
            flash("Skuff couldn’t read \(url.lastPathComponent).")
            return
        }
        let name = AppInspector.displayName(of: url)
        if tabs.first(where: { $0.id == id })?.appBundleIDs.contains(bundleID) == true {
            flash("\(name) is already in this tab.")
            return
        }
        if apps[bundleID] == nil {
            apps[bundleID] = InstalledApp(
                bundleID: bundleID,
                name: name,
                url: url,
                category: AppInspector.category(of: url)
            )
        }
        iconCache[bundleID] = nil
        addBundle(bundleID, name: name, to: id)
    }

    func openApp(_ bundleID: String) {
        guard let url = resolvedURL(for: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if error != nil {
                Task { @MainActor in NSSound.beep() }
            }
        }
    }

    func moveTab(_ id: UUID, by steps: Int) {
        guard steps != 0 else { return }
        var ordered = orderedTabs()
        guard let index = ordered.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(0, index + steps), ordered.count - 1)
        guard target != index else { return }
        let item = ordered.remove(at: index)
        ordered.insert(item, at: target)
        var changed = false
        for (offset, tab) in ordered.enumerated() where tab.sortOrder != offset {
            tab.sortOrder = offset
            tab.updatedAt = Date()
            changed = true
        }
        if changed { save() }
    }

    /// Writes a whole new tab order in one save, e.g. after a drag.
    func applyOrder(_ ids: [UUID]) {
        var changed = false
        for (offset, id) in ids.enumerated() {
            guard let tab = tabs.first(where: { $0.id == id }), tab.sortOrder != offset else { continue }
            tab.sortOrder = offset
            tab.updatedAt = Date()
            changed = true
        }
        if changed { save() }
    }

    func updateSettings(_ body: (inout SkuffSettings) -> Void) {
        var draft = settings
        body(&draft)
        draft.clamp()
        settings = draft
        SettingsStore.save(draft)
        refreshHotkeys()
        onChange?()
    }

    func replaceSettings(_ settings: SkuffSettings) {
        self.settings = settings
        SettingsStore.save(settings)
    }

    func applyTheme() {
        guard settings.theme.isFree || pro.isPro else {
            pro.lastError = "\(settings.theme.title) is part of Pro."
            return
        }
        let palette = settings.theme.palette
        let ordered = orderedTabs()
        for (index, tab) in ordered.enumerated() {
            tab.colorHex = palette[index % palette.count]
            tab.updatedAt = Date()
        }
        save()
    }

    func applyFontToAllTabs() {
        guard pro.isPro else {
            pro.lastError = "Custom fonts are part of Pro."
            return
        }
        var changed = false
        for tab in tabs {
            if tab.fontName != nil || tab.fontSize != nil || tab.fontWeight != nil {
                tab.fontName = nil
                tab.fontSize = nil
                tab.fontWeight = nil
                tab.updatedAt = Date()
                changed = true
            }
        }
        if changed { save() }
        onChange?()
    }

    /// Offsets are kept per screen *and* edge: a distance along a vertical edge means
    /// nothing on a horizontal one, so switching edges starts centered (or where that
    /// edge was last left).
    private func anchorKey(_ screenID: String) -> String {
        "\(screenID)#\(settings.edge.rawValue)"
    }

    func anchor(for screenID: String) -> ScreenAnchor {
        screenAnchors[anchorKey(screenID)] ?? ScreenAnchor()
    }

    /// `persist: false` while the grip is being dragged; the final position is saved on release.
    func setOffset(_ offset: Double, for screenID: String, notify: Bool = true, persist: Bool = true) {
        screenAnchors[anchorKey(screenID)] = ScreenAnchor(offset: offset)
        if persist { SettingsStore.saveAnchors(screenAnchors) }
        if notify { onChange?() }
    }

    func autoOrganize() {
        guard !organizing else { return }
        organizing = true
        defer { organizing = false }
        let placed = Set(tabs.flatMap(\.appBundleIDs))
        let unassigned = apps.values.filter { !placed.contains($0.bundleID) }
        let groups = Dictionary(grouping: unassigned, by: \.category)
        let keys = groups.keys.sorted { AppCategories.rank($0) < AppCategories.rank($1) }
        var working = tabs
        let existingAppCount = working.filter { $0.kind == .apps }.count
        let room = pro.isPro ? Int.max : max(0, (SkuffProduct.freeAppTabLimit + 1) - existingAppCount)
        var created = 0
        let palette = (pro.isPro ? settings.theme : .pastel).palette
        for key in keys {
            guard let matches = groups[key], !matches.isEmpty else { continue }
            let tab: FolderTabRecord
            if let existing = working.first(where: { $0.categoryKey == key }) {
                tab = existing
            } else {
                guard created < room else { break }
                let record = FolderTabRecord(
                    title: AppCategories.title(key),
                    colorHex: palette[working.count % palette.count],
                    sortOrder: (working.map(\.sortOrder).max() ?? -1) + 1,
                    categoryKey: key
                )
                record.icon = .sfSymbol(AppCategories.symbol(key))
                context.insert(record)
                working.append(record)
                created += 1
                tab = record
            }
            let sorted = matches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            var didAdd = false
            for app in sorted where !tab.appBundleIDs.contains(app.bundleID) {
                tab.appBundleIDs.append(app.bundleID)
                didAdd = true
            }
            if didAdd { tab.updatedAt = Date() }
        }
        save()
    }

    func chooseIcon(for id: UUID) async {
        guard pro.isPro else {
            pro.lastError = "Image icons are part of Pro."
            return
        }
        let panel = NSOpenPanel()
        var types: [UTType] = [.png, .jpeg, .heic, .pdf]
        if let svg = UTType(filenameExtension: "svg") { types.append(svg) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let filename = try await IconStore.importImage(from: url)
            setIcon(id, .image(filename))
        } catch {
            ioMessage = error.localizedDescription
        }
    }

    func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Skuff.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try ConfigTransfer.exportData(tabs: orderedTabs(), settings: settings)
            try data.write(to: url, options: .atomic)
            ioMessage = "Exported."
        } catch {
            ioMessage = error.localizedDescription
        }
    }

    func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert()
        alert.messageText = "Replace your tabs with this file?"
        alert.informativeText = "Tabs and settings in the file replace the ones on this Mac. Pro stays tied to your Apple ID."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let data = try Data(contentsOf: url)
            try ConfigTransfer.importDocument(data, into: self)
            ioMessage = "Imported."
        } catch {
            ioMessage = error.localizedDescription
        }
    }

    func showSettings() {
        settingsEpoch += 1
        presentSettings?()
    }

    func refreshHotkeys() {
        let toggle: (keyCode: UInt32, modifiers: UInt32)?
        if settings.toggleHotkeyEnabled {
            toggle = (
                UInt32(max(0, settings.toggleHotkeyKeyCode)),
                UInt32(max(0, settings.toggleHotkeyCarbonModifiers))
            )
        } else {
            toggle = nil
        }
        if settings.shortcutsEnabled {
            let result = HotkeyCenter.shared.register(count: min(9, tabs.count), toggle: toggle)
            failedHotkeys = result.failedTabs
            failedToggleHotkey = result.toggleFailed
        } else if let toggle {
            let result = HotkeyCenter.shared.register(count: 0, toggle: toggle)
            failedHotkeys = []
            failedToggleHotkey = result.toggleFailed
        } else {
            HotkeyCenter.shared.unregisterKeys()
            failedHotkeys = []
            failedToggleHotkey = false
        }
    }

    func requestTogglePanel() {
        presentTogglePanel?()
    }

    func beginRecordingToggleHotkey() {
        recordingToggleHotkey = true
        if let recordMonitor {
            NSEvent.removeMonitor(recordMonitor)
            self.recordMonitor = nil
        }
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let store = self else { return event }
            if event.keyCode == 53 {
                store.endRecordingToggleHotkey()
                return nil
            }
            let mods = HotkeyCenter.carbonModifiers(from: event.modifierFlags)
            guard mods != 0 else { return event }
            store.updateSettings {
                $0.toggleHotkeyKeyCode = Int(event.keyCode)
                $0.toggleHotkeyCarbonModifiers = mods
            }
            store.endRecordingToggleHotkey()
            return nil
        }
    }

    func endRecordingToggleHotkey() {
        recordingToggleHotkey = false
        if let recordMonitor {
            NSEvent.removeMonitor(recordMonitor)
            self.recordMonitor = nil
        }
    }

    func addFullScreenExclusion(bundleID: String, mode: FullScreenExclusionMode) {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        updateSettings { settings in
            settings.fullScreenExclusions.removeAll { $0.bundleID == id }
            settings.fullScreenExclusions.append(FullScreenAppRule(bundleID: id, mode: mode))
        }
    }

    func removeFullScreenExclusion(_ bundleID: String) {
        updateSettings { $0.fullScreenExclusions.removeAll { $0.bundleID == bundleID } }
    }

    func save() {
        try? context.save()
        reload()
        refreshHotkeys()
        onChange?()
    }

    private func addBundle(_ bundleID: String, name: String?, to id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        if let name { rememberName(name, for: bundleID) }
        guard !tab.appBundleIDs.contains(bundleID) else { return }
        tab.appBundleIDs.append(bundleID)
        tab.updatedAt = Date()
        save()
    }

    private func rememberName(_ name: String, for bundleID: String) {
        guard names[bundleID] != name else { return }
        names[bundleID] = name
        UserDefaults.standard.set(names, forKey: SettingsStore.namesKey)
    }

    private func applyFoundApps(_ found: [String: InstalledApp]) {
        var merged = found
        for (id, app) in apps where merged[id] == nil && FileManager.default.fileExists(atPath: app.url.path) {
            merged[id] = app
        }
        apps = merged
        iconCache.removeAll()
        var changed = false
        for app in merged.values where names[app.bundleID] != app.name {
            names[app.bundleID] = app.name
            changed = true
        }
        if changed {
            UserDefaults.standard.set(names, forKey: SettingsStore.namesKey)
        }
        considerInitialOrganize()
    }

    private func considerInitialOrganize() {
        if !tabs.isEmpty {
            UserDefaults.standard.set(true, forKey: SettingsStore.didOrganizeKey)
            return
        }
        guard !UserDefaults.standard.bool(forKey: SettingsStore.didOrganizeKey) else { return }
        seedDefaultTabs()
        UserDefaults.standard.set(true, forKey: SettingsStore.didOrganizeKey)
    }

    private func nextTitle(_ base: String) -> String {
        let titles = Set(tabs.map(\.title))
        if !titles.contains(base) { return base }
        var number = 2
        while titles.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    private func screenUnderMouse() -> String {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        return screen?.skuffID ?? "main"
    }

}

extension NSScreen {
    var skuffID: String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = deviceDescription[key] as? NSNumber {
            return number.stringValue
        }
        return "\(localizedName)-\(Int(frame.origin.x))-\(Int(frame.origin.y))"
    }
}
