import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class TabEditorDraft: ObservableObject {
    @Published var title: String
    @Published var colorHex: String
    @Published var iconKind: IconKind
    @Published var emoji: String
    @Published var symbol: String
    @Published var imageFilename: String?
    @Published var usesFolder: Bool
    @Published var folderPath: String
    @Published var folderBookmark: Data?
    @Published var isPinned: Bool
    @Published var customFont: Bool
    @Published var fontName: String?
    @Published var fontSize: Double
    @Published var fontWeight: Double
    @Published var iconSearch = ""
    @Published var showCustomColor = false
    @Published var customColor = Color.white
    @Published var appBundleIDs: [String] = []

    enum IconKind: String, CaseIterable, Identifiable {
        case symbols, emoji, image
        var id: String { rawValue }
        var title: String {
            switch self {
            case .symbols: "Symbols"
            case .emoji: "Emoji"
            case .image: "Image"
            }
        }
    }

    let palette: [String]
    let mode: TabEditorMode
    private let original: Snapshot?

    struct Snapshot {
        var title: String
        var colorHex: String
        var icon: TabIcon?
        var source: FolderSource?
        var isPinned: Bool
        var fontName: String?
        var fontSize: Double?
        var fontWeight: Double?
        var kind: TabKind
        var appBundleIDs: [String]
    }

    init(mode: TabEditorMode, store: LibraryStore, tab: FolderTabRecord?) {
        self.mode = mode
        self.palette = (store.pro.isPro ? store.settings.theme : .pastel).palette
        if let tab {
            title = tab.title
            colorHex = tab.colorHex
            switch tab.icon {
            case .emoji(let value):
                iconKind = .emoji
                emoji = value
                symbol = "folder"
            case .sfSymbol(let value):
                iconKind = .symbols
                symbol = value
                emoji = "📁"
            case .image(let value):
                iconKind = .image
                imageFilename = value
                emoji = "📁"
                symbol = "folder"
            case nil:
                iconKind = .symbols
                emoji = "📁"
                symbol = "folder"
            }
            usesFolder = tab.folderSource != nil
            folderPath = tab.folderSource?.path ?? ""
            folderBookmark = tab.folderSource?.bookmark
            isPinned = tab.isPinned
            customFont = tab.fontName != nil || tab.fontSize != nil || tab.fontWeight != nil
            fontName = tab.fontName
            fontSize = tab.fontSize ?? store.settings.globalFontSize
            fontWeight = tab.fontWeight ?? store.settings.globalFontWeight
            appBundleIDs = tab.appBundleIDs
            original = Snapshot(
                title: tab.title,
                colorHex: tab.colorHex,
                icon: tab.icon,
                source: tab.folderSource,
                isPinned: tab.isPinned,
                fontName: tab.fontName,
                fontSize: tab.fontSize,
                fontWeight: tab.fontWeight,
                kind: tab.kind,
                appBundleIDs: tab.appBundleIDs
            )
        } else {
            title = "New Tab"
            colorHex = palette.first ?? "F6C6CE"
            iconKind = .symbols
            emoji = "📁"
            symbol = "folder"
            usesFolder = false
            folderPath = ""
            isPinned = false
            customFont = false
            fontSize = store.settings.globalFontSize
            fontWeight = store.settings.globalFontWeight
            original = nil
        }
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var icon: TabIcon {
        switch iconKind {
        case .emoji:
            return TabIcon.emoji(emoji.isEmpty ? "📁" : String(emoji.prefix(8)))
        case .symbols:
            return TabIcon.sfSymbol(symbol)
        case .image:
            if let imageFilename { return TabIcon.image(imageFilename) }
            return TabIcon.sfSymbol(symbol)
        }
    }

    var folderSource: FolderSource? {
        if usesFolder {
            if !folderPath.isEmpty {
                var source = original?.source ?? FolderSource(path: folderPath, bookmark: folderBookmark)
                source.path = folderPath
                source.bookmark = folderBookmark
                return source
            }
            return original?.source
        }
        return nil
    }

    func applyLive(to store: LibraryStore, id: UUID) {
        store.rename(id, to: trimmedTitle.isEmpty ? "Untitled" : trimmedTitle)
        store.setColor(id, SkuffColor(hex: colorHex).color)
        store.setIcon(id, icon)
        store.setFolderSource(id, folderSource)
        store.replaceApps(id, with: appBundleIDs)
        if store.tabs.first(where: { $0.id == id })?.isPinned != isPinned {
            store.togglePin(id)
        }
        if ProFeature.customFonts.isUnlocked(in: store) {
            store.setFontOverride(id, enabled: customFont)
            if customFont {
                store.setTabFont(id, name: fontName, size: fontSize, weight: fontWeight)
            }
        }
        RecentIcons.remember(icon)
    }

    func revert(to store: LibraryStore, id: UUID) {
        guard let original else { return }
        store.rename(id, to: original.title)
        store.setColor(id, SkuffColor(hex: original.colorHex).color)
        store.setIcon(id, original.icon)
        store.setFolderSource(id, original.source)
        store.replaceApps(id, with: original.appBundleIDs)
        if store.tabs.first(where: { $0.id == id })?.isPinned != original.isPinned {
            store.togglePin(id)
        }
        store.setFontOverride(id, enabled: original.fontName != nil || original.fontSize != nil || original.fontWeight != nil)
        if let size = original.fontSize, let weight = original.fontWeight {
            store.setTabFont(id, name: original.fontName, size: size, weight: weight)
        }
    }
}

enum RecentIcons {
    private static let key = "skuff.recentIcons"

    static func remember(_ icon: TabIcon) {
        var items = load()
        let value: String
        switch icon {
        case .emoji(let text): value = "emoji:" + text
        case .sfSymbol(let text): value = "symbol:" + text
        case .image(let text): value = "image:" + text
        }
        items.removeAll { $0 == value }
        items.insert(value, at: 0)
        UserDefaults.standard.set(Array(items.prefix(8)), forKey: key)
    }

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func icon(from token: String) -> TabIcon? {
        if token.hasPrefix("emoji:") { return .emoji(String(token.dropFirst(6))) }
        if token.hasPrefix("symbol:") { return .sfSymbol(String(token.dropFirst(7))) }
        if token.hasPrefix("image:") { return .image(String(token.dropFirst(6))) }
        return nil
    }
}

struct TabEditorView: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var draft: TabEditorDraft
    var onCancel: () -> Void
    var onConfirm: () -> Void
    @FocusState private var nameFocused: Bool
    @State private var showAppPicker = false
    @State private var imageError: String?

    private let emojis = ["📁", "💼", "🎨", "🛠️", "📚", "⭐️", "🏠", "🧪", "🎬", "📷", "💻", "🧠", "🎵", "📝", "📦", "🚀"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 16)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    source
                    if !draft.usesFolder {
                        appsSection
                    }
                    colors
                    icons
                    DisclosureGroup("Advanced") {
                        Toggle("Pin", isOn: $draft.isPinned)
                        if ProFeature.customFonts.isUnlocked(in: store) {
                            Toggle("Custom font for this tab", isOn: $draft.customFont)
                            if draft.customFont {
                                FontControls(name: draft.fontName, size: draft.fontSize, weight: draft.fontWeight) { name, size, weight in
                                    draft.fontName = name
                                    draft.fontSize = size
                                    draft.fontWeight = weight
                                }
                            }
                        } else {
                            Text("Custom fonts are part of Pro.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.trimmedTitle.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 440, idealWidth: 440, maxWidth: .infinity, minHeight: 400, maxHeight: 640)
        .background(.background)
        .foregroundStyle(.primary)
        .onAppear { nameFocused = true }
        .onChange(of: draft.title) { _, _ in pushLive() }
        .onChange(of: draft.colorHex) { _, _ in pushLive() }
        .onChange(of: draft.symbol) { _, _ in pushLive() }
        .onChange(of: draft.emoji) { _, _ in pushLive() }
        .onChange(of: draft.imageFilename) { _, _ in pushLive() }
        .onChange(of: draft.folderPath) { _, _ in pushLive() }
        .onChange(of: draft.usesFolder) { _, _ in pushLive() }
        .onChange(of: draft.isPinned) { _, _ in pushLive() }
        .onChange(of: draft.customFont) { _, _ in pushLive() }
        .onChange(of: draft.appBundleIDs) { _, _ in pushLive() }
        .sheet(isPresented: $showAppPicker) {
            AppPickerView(store: store, selected: $draft.appBundleIDs, onDone: { showAppPicker = false })
        }
    }

    private var confirmTitle: String {
        if case .edit = draft.mode { return "Done" }
        return "Add"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            tabPreview
            TextField("Name", text: $draft.title)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(onConfirm)
        }
    }

    private var tabPreview: some View {
        let paint = SkuffColor(hex: draft.colorHex)
        let shape = store.settings.effectiveShape(isPro: store.pro.isPro)
        let face = TrapezoidTabShape(slant: shape.slant, cornerRadius: shape.cornerRadius, edge: .bottom, skew: shape.skew)
        return HStack(alignment: .bottom, spacing: -shape.overlap) {
            previewChip(face: face, paint: paint.dimmed(), active: false, shape: shape)
            previewChip(face: face, paint: paint, active: true, shape: shape)
        }
        .frame(width: 132, height: max(36, shape.tabWidth + 8))
        .accessibilityLabel("Tab preview")
    }

    private func previewChip(face: TrapezoidTabShape, paint: SkuffColor, active: Bool, shape: EffectiveShape) -> some View {
        ZStack {
            TabBackground(
                style: store.settings.tabFinish,
                face: face,
                paint: paint,
                palette: draft.palette.map { SkuffColor(hex: $0).color },
                locked: false,
                isActive: active,
                isHovered: false,
                reduceMotion: true,
                edge: .bottom
            )
            HStack(spacing: TabMetrics.make(settings: store.settings, isPro: store.pro.isPro).iconSpacing) {
                previewGlyph(paint.textColor)
                Text(draft.trimmedTitle.isEmpty ? "Tab" : draft.trimmedTitle)
                    .font(TabMetrics.make(settings: store.settings, isPro: store.pro.isPro).font)
                    .lineLimit(1)
            }
            .foregroundStyle(skuffTabInk(finish: store.settings.tabFinish, paint: paint))
            .padding(.horizontal, 10)
        }
        .frame(width: 78, height: max(28, shape.tabWidth))
    }

    @ViewBuilder
    private func previewGlyph(_ color: Color) -> some View {
        switch draft.icon {
        case .emoji(let value):
            Text(value).font(.system(size: 11))
        case .sfSymbol(let value):
            Image(systemName: value)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(color)
        case .image(let filename):
            if let image = IconStore.image(named: filename) {
                Image(nsImage: image).resizable().frame(width: 12, height: 12)
            }
        }
    }

    @ViewBuilder
    private var source: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Source").font(.headline)
            Picker("Source", selection: $draft.usesFolder) {
                Text("Apps").tag(false)
                Text(ProFeature.folderTabs.isUnlocked(in: store) ? "Folder" : "Folder 🔒").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if draft.usesFolder {
                if ProFeature.folderTabs.isUnlocked(in: store) {
                    HStack {
                        Text(draft.folderPath.isEmpty ? "Choose a folder…" : FolderAccess.displayPath(draft.folderPath))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !draft.folderPath.isEmpty {
                            Button {
                                draft.folderPath = ""
                                draft.folderBookmark = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear folder")
                        }
                        Button("Choose…") { pickFolder() }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Folder tabs and content search are Pro features")
                        Button(store.pro.upgradeLabel) { Task { await store.pro.purchase() } }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apps").font(.headline)
            if draft.appBundleIDs.isEmpty {
                Text("No apps yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(draft.appBundleIDs, id: \.self) { id in
                    HStack {
                        Image(nsImage: store.icon(for: id))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(store.displayName(for: id))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            draft.appBundleIDs.removeAll { $0 == id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(store.displayName(for: id))")
                    }
                }
            }
            Button("Add Apps…") { showAppPicker = true }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            store.acceptDropIntoDraft(providers, draft: draft)
            return true
        }
    }

    private var colors: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color").font(.headline)
            HStack(spacing: 8) {
                ForEach(draft.palette.prefix(8), id: \.self) { hex in
                    Button {
                        draft.colorHex = hex
                    } label: {
                        Circle()
                            .fill(SkuffColor(hex: hex).color)
                            .frame(width: 24, height: 24)
                            .overlay {
                                Circle().strokeBorder(Color.white, lineWidth: draft.colorHex == hex ? 2 : 0)
                            }
                            .overlay {
                                Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(hex)")
                    .accessibilityAddTraits(draft.colorHex == hex ? .isSelected : [])
                }
                ColorPicker("Custom color", selection: $draft.customColor, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: draft.customColor) { _, color in
                        draft.colorHex = SkuffColor(color: color).hex
                    }
                    .accessibilityLabel("Custom color")
            }
        }
    }

    private var icons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Icon").font(.headline)
            Picker("Icon", selection: $draft.iconKind) {
                ForEach(TabEditorDraft.IconKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            let recents = RecentIcons.load().compactMap { RecentIcons.icon(from: $0) }
            if !recents.isEmpty {
                Text("Recent").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(Array(recents.enumerated()), id: \.offset) { _, icon in
                        Button {
                            apply(icon)
                        } label: {
                            recentGlyph(icon)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            TextField("Search", text: $draft.iconSearch)
                .textFieldStyle(.roundedBorder)
            iconGrid
        }
    }

    @ViewBuilder
    private var iconGrid: some View {
        switch draft.iconKind {
        case .symbols:
            let query = draft.iconSearch.lowercased()
            let symbols = SFSymbolCatalog.symbols.filter { query.isEmpty || $0.contains(query) }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 6), count: 10), alignment: .leading, spacing: 6) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button {
                            draft.symbol = symbol
                        } label: {
                            Image(systemName: symbol)
                                .frame(width: 32, height: 32)
                                .background(draft.symbol == symbol ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                    }
                }
            }
            .frame(height: 180)
        case .emoji:
            let query = draft.iconSearch
            let shown = emojis.filter { query.isEmpty || $0.contains(query) }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 6), count: 10), alignment: .leading, spacing: 6) {
                    ForEach(shown, id: \.self) { emoji in
                        Button {
                            draft.emoji = emoji
                        } label: {
                            Text(emoji)
                                .frame(width: 32, height: 32)
                                .background(draft.emoji == emoji ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(emoji)
                    }
                }
            }
            .frame(height: 180)
            Button("More…") { NSApp.orderFrontCharacterPalette(nil) }
        case .image:
            if !ProFeature.imageIcons.isUnlocked(in: store) {
                Text("Image icons are part of Pro.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    if let filename = draft.imageFilename, let image = IconStore.image(named: filename) {
                        Image(nsImage: image)
                            .resizable()
                            .frame(width: 36, height: 36)
                        Button("Remove") { draft.imageFilename = nil }
                    }
                    Button("Choose Image…") { Task { await pickImage() } }
                }
                if let imageError {
                    Label(imageError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private func recentGlyph(_ icon: TabIcon) -> some View {
        switch icon {
        case .emoji(let value): Text(value)
        case .sfSymbol(let value): Image(systemName: value)
        case .image(let filename):
            if let image = IconStore.image(named: filename) {
                Image(nsImage: image).resizable()
            }
        }
    }

    private func apply(_ icon: TabIcon) {
        switch icon {
        case .emoji(let value):
            draft.iconKind = .emoji
            draft.emoji = value
        case .sfSymbol(let value):
            draft.iconKind = .symbols
            draft.symbol = value
        case .image(let value):
            draft.iconKind = .image
            draft.imageFilename = value
        }
    }

    private func pickFolder() {
        guard let url = FolderAccess.chooseFolder() else { return }
        draft.folderPath = url.path
        draft.folderBookmark = FolderAccess.bookmark(for: url)
        if draft.title == "New Tab" || draft.trimmedTitle.isEmpty {
            draft.title = url.lastPathComponent
        }
        draft.iconKind = .symbols
        draft.symbol = "folder"
    }

    private func pickImage() async {
        let panel = NSOpenPanel()
        var types: [UTType] = [.png, .jpeg, .heic, .pdf]
        if let svg = UTType(filenameExtension: "svg") { types.append(svg) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        imageError = nil
        do {
            draft.imageFilename = try await IconStore.importImage(from: url)
            draft.iconKind = .image
        } catch {
            imageError = error.localizedDescription
        }
    }

    private func pushLive() {
        if case .edit(let id) = draft.mode {
            draft.applyLive(to: store, id: id)
        }
    }
}

@MainActor
final class TabEditorPresenter {
    static let shared = TabEditorPresenter()
    private var window: NSPanel?
    private var draft: TabEditorDraft?

    func presentNew(store: LibraryStore) {
        show(store: store, mode: .new, tab: nil)
    }

    func presentEdit(store: LibraryStore, tab: FolderTabRecord) {
        show(store: store, mode: .edit(tab.id), tab: tab)
    }

    private func show(store: LibraryStore, mode: TabEditorMode, tab: FolderTabRecord?) {
        let draft = TabEditorDraft(mode: mode, store: store, tab: tab)
        self.draft = draft
        let root = TabEditorView(
            store: store,
            draft: draft,
            onCancel: { [weak self] in
                if case .edit(let id) = mode {
                    draft.revert(to: store, id: id)
                }
                self?.close()
            },
            onConfirm: { [weak self] in
                guard !draft.trimmedTitle.isEmpty else { return }
                switch mode {
                case .new:
                    store.commitNewTab(from: draft)
                case .edit(let id):
                    draft.applyLive(to: store, id: id)
                }
                self?.close()
            }
        )
        let host = NSHostingController(rootView: root)
        let panel = NSPanel(contentViewController: host)
        panel.styleMask = [.titled, .closable, .resizable]
        panel.title = modeTitle(mode)
        panel.minSize = NSSize(width: 440, height: 400)
        panel.maxSize = NSSize(width: 720, height: 640)
        panel.setContentSize(NSSize(width: 440, height: 560))
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 3)
        panel.isReleasedWhenClosed = false
        window = panel
        let wasAccessory = NSApp.activationPolicy() == .accessory
        if wasAccessory { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    private func modeTitle(_ mode: TabEditorMode) -> String {
        if case .edit = mode { return "Edit Tab" }
        return "New Tab"
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
        draft = nil
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
