import AppKit
import Combine
import Darwin
import Foundation
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

/// What decides which entries a folder tab lists. A change here re-reads the folder.
struct FolderListingKey: Equatable {
    var path: String
    var bookmark: Data?
    var showHidden: Bool
    var excludedNames: [String]

    init(source: FolderSource, settings: SkuffSettings) {
        path = source.path
        bookmark = source.bookmark
        showHidden = settings.folderShowHidden
        excludedNames = settings.folderExcludedNames
    }
}

@MainActor
final class FolderBrowserModel: ObservableObject {
    static let pageSize = 300

    @Published var items: [FolderItem] = []
    @Published var recent: [FolderItem] = []
    @Published var total = 0
    @Published var currentURL: URL?
    @Published var crumbs: [URL] = []
    @Published var error: FolderListingError?
    @Published var notIndexed = false
    @Published var loading = false
    @Published var contentMatches: [FolderItem] = []
    @Published var visibleCount = 0
    @Published var displayLimit = FolderBrowserModel.pageSize

    private var root: URL?
    private var scopedRoot: URL?
    private var attachedKey: FolderListingKey?
    private var source: FolderSource?
    private var watcher: DispatchSourceFileSystemObject?
    private var query: NSMetadataQuery?
    private var queryToken: NSObjectProtocol?
    private var searchDebounce: DispatchWorkItem?
    private var reloadDebounce: DispatchWorkItem?
    private var loadTask: Task<Void, Never>?
    /// Bumped on every new listing or search so late results from an older one are dropped.
    private var generation = 0
    private var contentVersion = 0
    private var visibleCache: (key: VisibleKey, items: [FolderItem])?
    private let quickLook = QuickLookBridge()

    private struct VisibleKey: Equatable {
        var version: Int
        var sort: FolderSortKey
        var ascending: Bool
        var typeFilter: [FileKind]
        var needle: String
    }

    /// Applies a tab's source together with the global folder settings. Hidden files and
    /// excluded names come from Settings, so changing them there updates every folder tab.
    func configure(source: FolderSource, settings: SkuffSettings, onRefreshedBookmark: (Data) -> Void) {
        var effective = source
        effective.showHidden = settings.folderShowHidden
        effective.excludedNames = settings.folderExcludedNames
        let key = FolderListingKey(source: source, settings: settings)
        guard let attachedKey else {
            attach(effective, key: key, onRefreshedBookmark: onRefreshedBookmark)
            return
        }
        if attachedKey.path != key.path || attachedKey.bookmark != key.bookmark {
            attach(effective, key: key, onRefreshedBookmark: onRefreshedBookmark)
        } else if attachedKey != key {
            self.attachedKey = key
            self.source = effective
            reload()
        } else {
            self.source = effective
        }
    }

    private func attach(_ source: FolderSource, key: FolderListingKey, onRefreshedBookmark: (Data) -> Void) {
        detach()
        self.source = source
        attachedKey = key
        displayLimit = Self.pageSize
        guard let resolution = FolderAccess.resolution(for: source) else {
            error = .missing
            items = []
            recent = []
            total = 0
            bumpContent()
            return
        }
        if let refreshed = resolution.refreshedBookmark {
            attachedKey?.bookmark = refreshed
            self.source?.bookmark = refreshed
            onRefreshedBookmark(refreshed)
        }
        let url = resolution.url
        if FolderAccess.start(url) {
            scopedRoot = url
        }
        root = url
        currentURL = url
        crumbs = [url]
        error = nil
        reload()
        watch(url)
    }

    func detach() {
        stopWatch()
        stopQuery()
        loadTask?.cancel()
        loadTask = nil
        searchDebounce?.cancel()
        reloadDebounce?.cancel()
        generation += 1
        loading = false
        if let scopedRoot { FolderAccess.stop(scopedRoot) }
        scopedRoot = nil
        root = nil
        attachedKey = nil
    }

    func reload() {
        guard let currentURL, let source else { return }
        stopQuery()
        generation += 1
        let token = generation
        loading = true
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                FolderListing.snapshot(url: currentURL, source: source)
            }.value
            guard let self, token == self.generation else { return }
            self.items = snapshot.items
            self.recent = snapshot.recent
            self.total = snapshot.total
            self.contentMatches = []
            self.notIndexed = false
            self.error = snapshot.error
            self.loading = false
            self.bumpContent()
        }
    }

    func visible(source: FolderSource, query: String) -> [FolderItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = VisibleKey(
            version: contentVersion,
            sort: source.sort,
            ascending: source.sortAscending,
            typeFilter: source.typeFilter,
            needle: needle
        )
        if let visibleCache, visibleCache.key == key { return visibleCache.items }
        let named = items.filter { item in
            guard FolderListing.matches(item, filters: source.typeFilter) else { return false }
            if needle.isEmpty { return true }
            return item.name.localizedStandardContains(needle)
        }
        let extra = contentMatches.filter { FolderListing.matches($0, filters: source.typeFilter) }
        let result = FolderListing.sort(named + extra, key: source.sort, ascending: source.sortAscending)
        visibleCache = (key, result)
        return result
    }

    func showMore() {
        displayLimit += Self.pageSize
    }

    func open(_ item: FolderItem) {
        if item.isDirectory {
            enter(item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func enter(_ url: URL) {
        currentURL = url
        displayLimit = Self.pageSize
        if let root {
            var chain: [URL] = []
            var cursor = url.standardizedFileURL
            let rootPath = root.standardizedFileURL.path
            while cursor.path == rootPath || cursor.path.hasPrefix(rootPath + "/") {
                chain.insert(cursor, at: 0)
                if cursor.path == rootPath { break }
                cursor = cursor.deletingLastPathComponent()
            }
            crumbs = chain.isEmpty ? [root] : chain
        }
        reload()
        if let currentURL { watch(currentURL) }
    }

    func goBack() {
        guard crumbs.count > 1 else { return }
        enter(crumbs[crumbs.count - 2])
    }

    func preview(_ item: FolderItem) {
        quickLook.show(item.url)
    }

    func search(query text: String, content: Bool) {
        searchDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.runSearch(text, content: content)
        }
        searchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func runSearch(_ text: String, content: Bool) {
        stopQuery()
        contentMatches = []
        notIndexed = false
        guard let currentURL, let source else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 2 {
            reload()
            return
        }
        generation += 1
        let token = generation
        loading = true
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let names = await Task.detached(priority: .userInitiated) {
                FolderListing.searchNames(root: currentURL, query: trimmed, source: source)
            }.value
            guard let self, token == self.generation else { return }
            self.items = names
            self.error = nil
            self.loading = false
            self.bumpContent()
            if content {
                self.startContentQuery(trimmed, in: currentURL, names: names, token: token)
            }
        }
    }

    private func startContentQuery(_ text: String, in url: URL, names: [FolderItem], token: Int) {
        let metadata = NSMetadataQuery()
        metadata.searchScopes = [url]
        metadata.predicate = NSPredicate(
            format: "(kMDItemDisplayName CONTAINS[cd] %@) OR (kMDItemTextContent CONTAINS[cd] %@)",
            text,
            text
        )
        queryToken = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: metadata,
            queue: .main
        ) { [weak self] _ in
            guard let model = self else { return }
            Task { @MainActor in model.collectContentMatches(names: names, token: token) }
        }
        query = metadata
        metadata.start()
    }

    private func collectContentMatches(names: [FolderItem], token: Int) {
        guard token == generation, let metadata = query else { return }
        metadata.disableUpdates()
        var matches: [FolderItem] = []
        let count = min(metadata.resultCount, 200)
        for index in 0..<count {
            guard let item = metadata.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: kMDItemPath as String) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            matches.append(
                FolderItem(
                    url: url,
                    name: url.lastPathComponent,
                    isDirectory: (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false,
                    modified: (item.value(forAttribute: kMDItemContentModificationDate as String) as? Date) ?? .distantPast,
                    size: (item.value(forAttribute: kMDItemFSSize as String) as? NSNumber)?.int64Value ?? 0,
                    contentMatch: true
                )
            )
        }
        notIndexed = matches.isEmpty && names.isEmpty == false && count == 0
        let named = Set(names.map(\.url.path))
        contentMatches = matches.filter { !named.contains($0.url.path) }
        bumpContent()
        metadata.enableUpdates()
    }

    private func stopQuery() {
        query?.stop()
        query = nil
        if let queryToken {
            NotificationCenter.default.removeObserver(queryToken)
        }
        queryToken = nil
    }

    private func bumpContent() {
        contentVersion += 1
    }

    private func watch(_ url: URL) {
        stopWatch()
        // The descriptor belongs to this source only; the cancel handler must not read
        // shared state, or cancelling an old watcher would close the new one's descriptor.
        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.debounceReload()
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
        }
        source.resume()
        watcher = source
    }

    private func debounceReload() {
        reloadDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        reloadDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func stopWatch() {
        watcher?.cancel()
        watcher = nil
    }
}

final class QuickLookBridge: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var url: URL?

    func show(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as NSURL?
    }
}

struct FolderBrowserView: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var model: FolderBrowserModel
    var tab: FolderTabRecord
    var query: String
    @State private var selection: FolderItem.ID?

    var body: some View {
        let source = tab.folderSource
        VStack(alignment: .leading, spacing: 10) {
            if !ProFeature.folderTabs.isUnlocked(in: store) {
                upgrade
            } else if let source {
                let shown = model.visible(source: source, query: query)
                controls(source, count: model.visibleCount)
                listing(source, shown: shown)
                    .onAppear { model.visibleCount = shown.count }
                    .onChange(of: shown.count) { _, count in model.visibleCount = count }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { configureModel() }
        .onDisappear { model.detach() }
        .onChange(of: listingKey) { _, _ in configureModel() }
        .onChange(of: query) { _, value in
            guard let source else { return }
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model.reload()
            } else {
                model.search(query: value, content: source.searchContent && ProFeature.contentSearch.isUnlocked(in: store))
            }
        }
        .focusable()
        .onKeyPress(.space) {
            if let item = selectedItem {
                model.preview(item)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.return) {
            if let item = selectedItem {
                model.open(item)
                return .handled
            }
            return .ignored
        }
    }

    private var listingKey: FolderListingKey? {
        tab.folderSource.map { FolderListingKey(source: $0, settings: store.settings) }
    }

    private func configureModel() {
        guard let source = tab.folderSource else { return }
        let id = tab.id
        model.configure(source: source, settings: store.settings) { refreshed in
            store.refreshFolderBookmark(id, refreshed)
        }
    }

    private var upgrade: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Folder tabs and content search are Pro features")
                .font(.headline)
            Button(store.pro.upgradeLabel) { Task { await store.pro.purchase() } }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func controls(_ source: FolderSource, count: Int) -> some View {
        HStack(spacing: 8) {
            if model.crumbs.count > 1 {
                Button("Back") { model.goBack() }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(model.crumbs.enumerated()), id: \.offset) { index, url in
                        if index > 0 { Text("›").foregroundStyle(.secondary) }
                        Button(url.lastPathComponent) { model.enter(url) }
                            .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
            Picker("View", selection: Binding(
                get: { source.viewMode },
                set: { mode in store.setFolderSource(tab.id) { $0.viewMode = mode } }
            )) {
                Image(systemName: "square.grid.2x2").tag(FolderViewMode.grid)
                Image(systemName: "list.bullet").tag(FolderViewMode.list)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 72)
            .accessibilityLabel("View")
            Menu("Sort") {
                ForEach(FolderSortKey.allCases) { key in
                    Button(key.title) { store.setFolderSource(tab.id) { $0.sort = key } }
                }
                Divider()
                Button(source.sortAscending ? "Descending" : "Ascending") {
                    store.setFolderSource(tab.id) { $0.sortAscending.toggle() }
                }
            }
            Text(skuffItemCount(count))
                .font(.caption)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.secondary)
        }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("All", selected: source.typeFilter.isEmpty) {
                    store.setFolderSource(tab.id) { $0.typeFilter = [] }
                }
                ForEach(FileKind.allCases) { kind in
                    chip(kind.title, selected: source.typeFilter.contains(kind)) {
                        store.setFolderSource(tab.id) { current in
                            if let index = current.typeFilter.firstIndex(of: kind) {
                                current.typeFilter.remove(at: index)
                            } else {
                                current.typeFilter.append(kind)
                            }
                        }
                    }
                }
            }
            .padding(.trailing, 28)
        }
        .mask(
            HStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 28)
            }
        )
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .tint(selected ? Color.accentColor : nil)
            .controlSize(.small)
    }

    @ViewBuilder
    private func listing(_ source: FolderSource, shown: [FolderItem]) -> some View {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if model.error == .missing {
            notice(
                "Folder not found",
                detail: "\(FolderAccess.displayPath(source.path)) isn’t on this Mac.",
                symbol: "questionmark.folder"
            ) {
                Button("Choose another folder…") { store.chooseFolder(for: tab.id) }
            }
        } else if model.error == .denied {
            notice(
                "Skuff can’t read this folder",
                detail: "Choose \(FolderAccess.displayPath(source.path)) again to give Skuff access.",
                symbol: "lock.circle"
            ) {
                Button("Grant Access…") { store.grantFolderAccess(for: tab.id) }
                Button("Open Privacy Settings") { FolderAccess.openPrivacySettings() }
                    .buttonStyle(.link)
            }
        } else if model.loading, shown.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(searching ? "Searching…" : "Loading…").foregroundStyle(.secondary)
            }
        } else if model.error == .empty, !searching, shown.isEmpty {
            notice("This folder is empty", detail: emptyDetail(source), symbol: "folder")
        } else if shown.isEmpty, searching {
            Text("No results for ‘\(query)’")
                .foregroundStyle(.secondary)
            Text("Try Name + Content, or clear the filters.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if shown.isEmpty {
            notice("Nothing matches these filters", detail: nil, symbol: "line.3.horizontal.decrease.circle") {
                Button("Show all") { store.setFolderSource(tab.id) { $0.typeFilter = [] } }
            }
        } else {
            if model.notIndexed {
                Text("Content isn’t indexed for this folder. Showing name matches only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !searching, !model.recent.isEmpty {
                        Text("Recent")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        files(model.recent, source: source)
                        Divider()
                    }
                    files(Array(shown.prefix(model.displayLimit)), source: source)
                    if shown.count > model.displayLimit {
                        Button("Show \(min(FolderBrowserModel.pageSize, shown.count - model.displayLimit)) more") {
                            model.showMore()
                        }
                        .buttonStyle(.link)
                        .frame(maxWidth: .infinity)
                    }
                    if model.total > FolderListing.cap, !searching {
                        Text("Showing the first \(FolderListing.cap.formatted()) of \(model.total.formatted()) items. Open the folder in Finder to see the rest.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func emptyDetail(_ source: FolderSource) -> String? {
        if !source.showHidden, !source.excludedNames.isEmpty {
            return "Hidden files and excluded names aren’t shown. Change this in Settings › Folder."
        }
        if !source.showHidden {
            return "Hidden files aren’t shown. Change this in Settings › Folder."
        }
        return nil
    }

    @ViewBuilder
    private func files(_ items: [FolderItem], source: FolderSource) -> some View {
        if source.viewMode == .grid {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 10)], spacing: 12) {
                ForEach(items) { item in
                    fileTile(item)
                }
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(items) { item in
                    fileRow(item)
                }
            }
        }
    }

    private func fileTile(_ item: FolderItem) -> some View {
        VStack(spacing: 4) {
            FileGlyph(item: item, side: 48, thumbnails: store.settings.folderThumbnails)
            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
            if item.contentMatch {
                Text("Content match").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .help(helpText(item))
        .padding(4)
        .contentShape(Rectangle())
        .background(selection == item.id ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .onTapGesture(count: 2) { model.open(item) }
        .onTapGesture { selection = item.id }
        .contextMenu { fileMenu(item) }
        .draggable(item.url)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(item))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.open(item) }
    }

    private func fileRow(_ item: FolderItem) -> some View {
        HStack(spacing: 8) {
            FileGlyph(item: item, side: 24, thumbnails: store.settings.folderThumbnails)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                if item.contentMatch {
                    Text("Content match").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(detailText(item))
                .font(.caption)
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(.secondary)
            if item.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .help(helpText(item))
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .background(selection == item.id ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .onTapGesture(count: 2) { model.open(item) }
        .onTapGesture { selection = item.id }
        .contextMenu { fileMenu(item) }
        .draggable(item.url)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(item))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.open(item) }
    }

    private func detailText(_ item: FolderItem) -> String {
        let date = item.modified == .distantPast ? "" : item.modified.formatted(date: .abbreviated, time: .omitted)
        if item.isDirectory { return date }
        let size = item.size.formatted(.byteCount(style: .file))
        return date.isEmpty ? size : "\(date) · \(size)"
    }

    private func helpText(_ item: FolderItem) -> String {
        let detail = detailText(item)
        let path = FolderAccess.displayPath(item.url.path)
        return detail.isEmpty ? path : "\(path)\n\(detail)"
    }

    private func accessibilityText(_ item: FolderItem) -> String {
        let kind = item.isDirectory ? "Folder" : "File"
        let detail = detailText(item)
        return detail.isEmpty ? "\(kind), \(item.name)" : "\(kind), \(item.name), \(detail)"
    }

    private var selectedItem: FolderItem? {
        guard let selection else { return nil }
        return (model.items + model.recent + model.contentMatches).first { $0.id == selection }
    }

    @ViewBuilder
    private func fileMenu(_ item: FolderItem) -> some View {
        Button("Open") { model.open(item) }
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: item.url)
        if !apps.isEmpty {
            Menu("Open With") {
                ForEach(apps.prefix(8), id: \.path) { app in
                    Button(app.deletingPathExtension().lastPathComponent) {
                        NSWorkspace.shared.open(
                            [item.url],
                            withApplicationAt: app,
                            configuration: NSWorkspace.OpenConfiguration()
                        )
                    }
                }
            }
        }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.url.path, forType: .string) }
        Button("Quick Look") { model.preview(item) }
    }

    private func notice(
        _ title: String,
        detail: String?,
        symbol: String,
        @ViewBuilder actions: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) { actions() }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// File icon that swaps in a Quick Look thumbnail once one is ready.
struct FileGlyph: View {
    var item: FolderItem
    var side: CGFloat
    var thumbnails: Bool
    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: side > 32 ? 4 : 2, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
            } else {
                Image(nsImage: FolderThumbnails.shared.icon(for: item.url))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
        .task(id: taskID) {
            guard thumbnails, !item.isDirectory else {
                thumbnail = nil
                return
            }
            thumbnail = await FolderThumbnails.shared.thumbnail(for: item, side: side, scale: displayScale)
        }
    }

    private var taskID: String {
        "\(item.id)|\(item.modified.timeIntervalSinceReferenceDate)|\(thumbnails)|\(Int(side))"
    }
}
