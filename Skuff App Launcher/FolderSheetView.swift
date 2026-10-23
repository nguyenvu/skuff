import AppKit
import SwiftUI
import UniformTypeIdentifiers

@ViewBuilder
private func folderBackground(store: LibraryStore, color: Color) -> some View {
    if store.settings.connectedTab {
        Color.clear
    } else {
        FolderChrome(color: color, finish: store.settings.tabFinish, shape: Rectangle())
    }
}

/// Text color inside a folder: follows the tab's finish, so glass folders use system ink.
private func folderInk(store: LibraryStore, paint: SkuffColor) -> Color {
    skuffTabInk(finish: store.settings.tabFinish, paint: paint)
}

private func folderInsets(store: LibraryStore, base: CGFloat) -> EdgeInsets {
    let shape = store.settings.effectiveShape(isPro: store.pro.isPro)
    let tongue = shape.tabWidth + 20
    switch store.settings.edge {
    case .left:
        return EdgeInsets(top: base, leading: tongue, bottom: base, trailing: base)
    case .right:
        return EdgeInsets(top: base, leading: base, bottom: base, trailing: tongue)
    case .top:
        return EdgeInsets(top: tongue, leading: base, bottom: base, trailing: base)
    case .bottom:
        return EdgeInsets(top: base, leading: base, bottom: tongue, trailing: base)
    }
}

/// Folder background. Glass finishes match their tabs: Liquid is plain system glass,
/// Glass is lightly tinted. Other finishes fill the folder with the tab's color.
private struct FolderChrome<S: Shape>: View {
    var color: Color
    var finish: TabFinish
    var shape: S

    var body: some View {
        switch finish {
        case .liquid:
            ZStack {
                Color.clear.glassEffect(.regular, in: shape)
                // Keeps the glass clickable; see TabBackground.
                shape.fill(Color.black.opacity(0.01))
            }
        case .glass:
            ZStack {
                Color.clear.glassEffect(.regular.tint(color.opacity(0.25)), in: shape)
                shape.fill(Color.black.opacity(0.01))
            }
        default:
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                color.opacity(0.72)
            }
        }
    }
}

struct FolderSheetContainer: View {
    @ObservedObject var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if store.settings.connectedTab, store.openBump.width > 2 {
                connectedBody
            } else {
                sheetContent
                    .clipShape(folderFace)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.openTabID)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: store.openBump)
    }

    @ViewBuilder
    private var sheetContent: some View {
        if let id = store.openTabID, let tab = store.tabs.first(where: { $0.id == id }) {
            Group {
                if tab.kind == .smartFilter {
                    LaterKindView(store: store, tab: tab)
                } else if tab.kind == .apps, store.isBeyondFreeLimit(tab) {
                    UpgradeCard(store: store, tab: tab)
                } else {
                    FolderSheetView(store: store, tabID: tab.id)
                }
            }
            .id(tab.id)
        } else {
            Color.clear
        }
    }

    private var connectedBody: some View {
        let face = skuffFolderShape(store: store, tabRect: store.openBump)
        return ZStack(alignment: .topLeading) {
            connectedChrome
            sheetContent
                .clipShape(face)
            Color.clear
                .frame(width: store.openBump.width, height: store.openBump.height)
                .contentShape(Rectangle())
                .offset(x: store.openBump.minX, y: store.openBump.minY)
                // Same click tolerance as the strip's tabs, so a slightly moving click still closes.
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            guard hypot(value.translation.width, value.translation.height) < 8,
                                  let id = store.openTabID else { return }
                            store.toggleTab(id, on: store.openScreenID ?? "")
                        }
                )
        }
    }

    private var connectedChrome: some View {
        let tab = store.tabs.first { $0.id == store.openTabID }
        let paint = SkuffColor(hex: tab?.colorHex ?? "F6C6CE")
        let face = skuffFolderShape(store: store, tabRect: store.openBump)
        let shadow = store.settings.tabShadow
        let offset = tabShadowOffset
        return ZStack {
            FolderChrome(color: paint.color, finish: store.settings.tabFinish, shape: face)
            if store.settings.paperEdge {
                face.stroke(Color.white.opacity(0.35), lineWidth: 1)
                    .blendMode(.overlay)
                face.stroke(Color.black.opacity(0.12), lineWidth: 1)
                    .offset(x: offset.width * 0.15, y: offset.height * 0.15)
            }
        }
        .clipShape(face)
        .shadow(color: Color.black.opacity(0.12 + 0.25 * shadow), radius: 4 + 4 * shadow, x: offset.width, y: offset.height)
        .overlay(alignment: .topLeading) {
            if let tab {
                tongueLabel(tab, paint: paint)
                    .frame(width: store.openBump.width, height: store.openBump.height)
                    .offset(x: store.openBump.minX, y: store.openBump.minY)
                    .allowsHitTesting(false)
            }
        }
    }

    private var tabShadowOffset: CGSize {
        let step: CGFloat = 3
        switch store.settings.edge {
        case .left: return CGSize(width: -step, height: 0)
        case .right: return CGSize(width: step, height: 0)
        case .top: return CGSize(width: 0, height: -step)
        case .bottom: return CGSize(width: 0, height: step)
        }
    }

    @ViewBuilder
    private func tongueLabel(_ tab: FolderTabRecord, paint: SkuffColor) -> some View {
        let ink = skuffTabInk(finish: store.settings.tabFinish, paint: paint)
        let horizontal = store.settings.edge.runsAlongX
        let title = tab.title
        Group {
            if horizontal {
                HStack(spacing: 6) {
                    tongueGlyph(tab, color: ink)
                    Text(title)
                        .font(TabMetrics.make(settings: store.settings, isPro: store.pro.isPro).font)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                RotatedTabLabel {
                    HStack(spacing: TabMetrics.make(settings: store.settings, isPro: store.pro.isPro).iconSpacing) {
                        tongueGlyph(tab, color: ink)
                        Text(title)
                            .font(TabMetrics.make(settings: store.settings, isPro: store.pro.isPro).font)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                }
            }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }

    @ViewBuilder
    private func tongueGlyph(_ tab: FolderTabRecord, color: Color) -> some View {
        if let symbol = tab.iconSymbol, !symbol.isEmpty {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(color)
        } else if let emoji = tab.iconEmoji, !emoji.isEmpty {
            Text(emoji).font(.system(size: 12))
        } else {
            Image(systemName: "folder")
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(color)
        }
    }

    private var folderFace: UnevenRoundedRectangle {
        let outer: CGFloat = 18
        let joint: CGFloat = 0
        let radii: RectangleCornerRadii
        switch store.settings.edge {
        case .right:
            radii = RectangleCornerRadii(topLeading: outer, bottomLeading: outer, bottomTrailing: joint, topTrailing: joint)
        case .left:
            radii = RectangleCornerRadii(topLeading: joint, bottomLeading: joint, bottomTrailing: outer, topTrailing: outer)
        case .top:
            radii = RectangleCornerRadii(topLeading: joint, bottomLeading: outer, bottomTrailing: outer, topTrailing: joint)
        case .bottom:
            radii = RectangleCornerRadii(topLeading: outer, bottomLeading: joint, bottomTrailing: joint, topTrailing: outer)
        }
        return UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
    }
}

private struct UpgradeCard: View {
    @ObservedObject var store: LibraryStore
    var tab: FolderTabRecord

    var body: some View {
        let paint = SkuffColor(hex: tab.colorHex)
        VStack(spacing: 12) {
            Image(systemName: "lock")
                .font(.title2)
            Text(tab.title)
                .font(.headline)
            Text("You can use 5 app tabs. This one unlocks with Pro.")
                .font(.callout)
                .multilineTextAlignment(.center)
            Button(store.pro.upgradeLabel) {
                Task { await store.pro.purchase() }
            }
            .keyboardShortcut(.defaultAction)
            Button("Restore Purchases") {
                Task { await store.pro.restore() }
            }
            if let error = store.pro.lastError {
                Text(error)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            Button("Delete Tab") { store.requestDeleteTab(tab.id) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(folderInk(store: store, paint: paint))
        .padding(folderInsets(store: store, base: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { folderBackground(store: store, color: paint.color) }
        .accessibilityElement(children: .contain)
    }
}

private struct LaterKindView: View {
    @ObservedObject var store: LibraryStore
    var tab: FolderTabRecord

    var body: some View {
        let paint = SkuffColor(hex: tab.colorHex)
        VStack(spacing: 10) {
            Text(tab.title).font(.headline)
            Text(tab.kind == .folders
                 ? "Folder tabs are not in this version yet."
                 : "Smart filter tabs are not in this version yet.")
                .font(.callout)
                .multilineTextAlignment(.center)
            if !store.pro.isPro {
                Text("They will be part of Pro.")
                    .font(.caption)
            }
        }
        .foregroundStyle(folderInk(store: store, paint: paint))
        .padding(folderInsets(store: store, base: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { folderBackground(store: store, color: paint.color) }
    }
}

/// Natural height of the app grid (or empty state) inside the folder.
private struct FitContentKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Height the folder currently gives that grid.
private struct FitViewportKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct FitHeights: Equatable {
    var content: CGFloat = 0
    var viewport: CGFloat = 0
}

struct FolderSheetView: View {
    @ObservedObject var store: LibraryStore
    var tabID: UUID
    @StateObject private var folderModel = FolderBrowserModel()
    @State private var query = ""
    @State private var editing = false
    /// App picked with the arrow keys; Return opens it.
    @State private var selectedApp: String?
    @State private var fit = FitHeights()
    @FocusState private var searchFocused: Bool

    /// Column counts of the two grids, used for up/down navigation.
    private static let pinnedColumns = 3
    private static let appColumns = 4

    private var tab: FolderTabRecord? {
        store.tabs.first { $0.id == tabID }
    }

    var body: some View {
        Group {
            if let tab {
                let paint = SkuffColor(hex: tab.colorHex)
                let folderCount = tab.folderSource == nil ? 0 : folderModel.visibleCount
                VStack(alignment: .leading, spacing: 12) {
                    header(tab, paint: paint, itemCount: tab.appBundleIDs.count + folderCount)
                    searchRow(tab)
                    if tab.appBundleIDs.isEmpty, tab.folderSource == nil {
                        emptyApps(tab)
                            .background { heightProbe(FitContentKey.self) }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .background { heightProbe(FitViewportKey.self) }
                    } else {
                        appGrid(tab, paint: paint, fills: tab.folderSource == nil, editing: editing)
                    }
                    if tab.folderSource != nil {
                        FolderBrowserView(store: store, model: folderModel, tab: tab, query: query)
                    }
                }
                .padding(folderInsets(store: store, base: TabMetrics.make(settings: store.settings, isPro: store.pro.isPro).panelPadding))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background { folderBackground(store: store, color: paint.color) }
                .foregroundStyle(folderInk(store: store, paint: paint))
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    store.acceptDrop(providers, onto: tab.id)
                    return true
                }
                .onExitCommand { store.closeFolder() }
                .onAppear {
                    if NSApp.isActive || store.folderWantsKeyboard {
                        // The panel becomes key right after it appears; focus on the next pass.
                        DispatchQueue.main.async { searchFocused = true }
                    }
                }
                .onChange(of: store.searchFocusRequest) { _, _ in
                    searchFocused = true
                }
                .onPreferenceChange(FitContentKey.self) { value in fit.content = value }
                .onPreferenceChange(FitViewportKey.self) { value in fit.viewport = value }
                .onChange(of: fit) { _, value in
                    // Folder tabs scroll their own file list, so they keep the full height.
                    // While searching the grid shrinks; keep the size so the field stays put.
                    guard tab.folderSource == nil, query.isEmpty, value.content > 1, value.viewport > 1 else { return }
                    store.reportSheetSlack(value.viewport - value.content, for: tab.id)
                }
                .onChange(of: query) { _, _ in
                    let order = appOrder(tab)
                    selectedApp = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil
                        : (order.pinned + order.rest).first
                }
            }
        }
    }

    private func header(_ tab: FolderTabRecord, paint: SkuffColor, itemCount: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(skuffItemCount(itemCount))
                    .font(.caption)
                    .opacity(0.75)
            }
            Spacer()
            Button(editing ? "Done" : "Edit") { editing.toggle() }
                .buttonStyle(.bordered)
                .tint(folderInk(store: store, paint: paint))
                .accessibilityLabel(editing ? "Done managing apps" : "Manage apps in this tab")
        }
    }

    private func searchRow(_ tab: FolderTabRecord) -> some View {
        HStack(spacing: 8) {
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit { openSelectedApp(tab) }
                .onKeyPress(.downArrow) { moveSelection(tab, dx: 0, dy: 1) }
                .onKeyPress(.upArrow) { moveSelection(tab, dx: 0, dy: -1) }
                .onKeyPress(.leftArrow) { query.isEmpty ? moveSelection(tab, dx: -1, dy: 0) : .ignored }
                .onKeyPress(.rightArrow) { query.isEmpty ? moveSelection(tab, dx: 1, dy: 0) : .ignored }
                .accessibilityLabel("Search this tab")
                .accessibilityHint("Type to filter. Use the arrow keys to pick an app and Return to open it.")
            if tab.folderSource != nil {
                Picker("Search mode", selection: Binding(
                    get: { tab.folderSource?.searchContent ?? true },
                    set: { value in
                        guard ProFeature.contentSearch.isUnlocked(in: store) else {
                            store.promptFolderUpgrade()
                            return
                        }
                        store.setFolderSource(tab.id) { $0.searchContent = value }
                    }
                )) {
                    Text("Name").frame(maxWidth: .infinity).tag(false)
                    Text(ProFeature.contentSearch.isUnlocked(in: store) ? "Name + Content" : "Name + Content 🔒")
                        .frame(maxWidth: .infinity)
                        .tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 228)
                .accessibilityLabel("Search names or file contents")
            }
        }
    }

    private func emptyApps(_ tab: FolderTabRecord) -> some View {
        VStack(spacing: 10) {
            Text("No apps yet")
                .font(.headline)
            Button("Add Apps") {
                AppPickerPresenter.shared.present(store: store, selected: tab.appBundleIDs) { ids in
                    store.replaceApps(tab.id, with: ids)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func heightProbe<Key: PreferenceKey>(_ key: Key.Type) -> some View where Key.Value == CGFloat {
        GeometryReader { geo in
            Color.clear.preference(key: key, value: geo.size.height)
        }
    }

    /// Apps matching the search, split the way the grids show them.
    private func appOrder(_ tab: FolderTabRecord) -> (pinned: [String], rest: [String]) {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = tab.appBundleIDs.filter { id in
            guard !needle.isEmpty else { return true }
            return store.displayName(for: id).lowercased().contains(needle) || id.lowercased().contains(needle)
        }
        let pinned = tab.pinnedAppBundleIDs.filter { matches.contains($0) }
        return (pinned, matches.filter { !pinned.contains($0) })
    }

    private func openSelectedApp(_ tab: FolderTabRecord) {
        let order = appOrder(tab)
        guard let bundleID = selectedApp ?? (order.pinned + order.rest).first else { return }
        guard store.isInstalled(bundleID) else {
            NSSound.beep()
            return
        }
        store.openApp(bundleID)
    }

    private func moveSelection(_ tab: FolderTabRecord, dx: Int, dy: Int) -> KeyPress.Result {
        let order = appOrder(tab)
        let all = order.pinned + order.rest
        guard !all.isEmpty else { return .ignored }
        guard let current = selectedApp, let flat = all.firstIndex(of: current) else {
            selectedApp = all.first
            return .handled
        }
        if dx != 0 {
            selectedApp = all[min(max(flat + dx, 0), all.count - 1)]
            return .handled
        }
        let inPinned = flat < order.pinned.count
        let section = inPinned ? order.pinned : order.rest
        let columns = inPinned ? Self.pinnedColumns : Self.appColumns
        let index = inPinned ? flat : flat - order.pinned.count
        let column = index % columns
        let target = index + dy * columns
        if section.indices.contains(target) {
            selectedApp = section[target]
        } else if dy > 0, inPinned, !order.rest.isEmpty {
            selectedApp = order.rest[min(column, order.rest.count - 1)]
        } else if dy < 0, !inPinned, !order.pinned.isEmpty {
            let lastRow = (order.pinned.count - 1) / Self.pinnedColumns * Self.pinnedColumns
            selectedApp = order.pinned[min(lastRow + column, order.pinned.count - 1)]
        } else if dy > 0, index / columns < (section.count - 1) / columns {
            // Moving into a short last row: land on its final item.
            selectedApp = section[section.count - 1]
        }
        return .handled
    }

    private func appGrid(_ tab: FolderTabRecord, paint: SkuffColor, fills: Bool, editing: Bool) -> some View {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let (pinned, rest) = appOrder(tab)
        let matches = pinned + rest
        let content = Group {
            if matches.isEmpty && !needle.isEmpty {
                Text("No matches")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if !pinned.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Favorites")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: Self.pinnedColumns), spacing: 14) {
                                ForEach(pinned, id: \.self) { bundleID in
                                    appTile(bundleID, tabID: tab.id, pinned: true, editing: editing)
                                }
                            }
                        }
                    }
                    if !rest.isEmpty || editing {
                        VStack(alignment: .leading, spacing: 8) {
                            if !pinned.isEmpty {
                                Text("Apps")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: Self.appColumns), spacing: 16) {
                                ForEach(rest, id: \.self) { bundleID in
                                    appTile(bundleID, tabID: tab.id, pinned: false, editing: editing)
                                }
                                if editing {
                                    addAppTile(tab)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        if fills {
            return AnyView(
                ScrollViewReader { proxy in
                    ScrollView {
                        content.background { heightProbe(FitContentKey.self) }
                    }
                    .frame(maxHeight: .infinity)
                    .background { heightProbe(FitViewportKey.self) }
                    .onChange(of: selectedApp) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                    }
                }
            )
        }
        return AnyView(content)
    }

    private func addAppTile(_ tab: FolderTabRecord) -> some View {
        Button {
            AppPickerPresenter.shared.present(store: store, selected: tab.appBundleIDs) { ids in
                store.replaceApps(tab.id, with: ids)
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .frame(width: 44, height: 44)
                Text("Add")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add apps")
    }

    private func appTile(_ bundleID: String, tabID: UUID, pinned: Bool, editing: Bool) -> some View {
        let installed = store.isInstalled(bundleID)
        let running = store.runningBundleIDs.contains(bundleID)
        let name = store.displayName(for: bundleID)
        let icon: CGFloat = pinned ? 68 : 44
        let selected = selectedApp == bundleID
        return Button {
            guard installed else { return }
            store.openApp(bundleID)
        } label: {
            VStack(spacing: 4) {
                Image(nsImage: store.icon(for: bundleID))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: icon, height: icon)
                    .opacity(installed ? 1 : 0.35)
                Circle()
                    .fill(running ? Color(red: 0.18, green: 0.72, blue: 0.34) : Color.clear)
                    .frame(width: 5, height: 5)
                Text(name)
                    .font(pinned ? .callout.weight(.semibold) : .caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .opacity(installed ? 1 : 0.45)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                }
            }
        }
        .buttonStyle(.plain)
        .id(bundleID)
        .help(installed ? name : "\(name) isn’t installed on this Mac")
        .overlay(alignment: .topTrailing) {
            if editing {
                Button {
                    store.removeApp(bundleID, from: tabID)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .accessibilityLabel("Remove \(name)")
            }
        }
        .overlay(alignment: .topLeading) {
            if editing {
                Button {
                    store.toggleFavorite(bundleID, in: tabID)
                } label: {
                    Image(systemName: pinned ? "star.fill" : "star")
                        .foregroundStyle(pinned ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .offset(x: -4, y: -4)
                .accessibilityLabel(pinned ? "Unpin favorite" : "Pin to favorites")
            }
        }
        .contextMenu {
            Button(pinned ? "Unpin Favorite" : "Pin to Favorites") {
                store.toggleFavorite(bundleID, in: tabID)
            }
            Button("Remove", role: .destructive) {
                store.removeApp(bundleID, from: tabID)
            }
        }
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(running ? "Running" : (installed ? (pinned ? "Favorite" : "") : "Not installed"))
        .accessibilityHint(installed ? "Opens the app." : "This app is not on this Mac.")
    }

}

struct FontControls: View {
    var name: String?
    var size: Double
    var weight: Double
    var onChange: (String?, Double, Double) -> Void
    @State private var families: [String] = []

    var body: some View {
        VStack(alignment: .leading) {
            Picker("Family", selection: Binding(
                get: { name ?? "" },
                set: { onChange($0.isEmpty ? nil : $0, size, weight) }
            )) {
                Text("System").tag("")
                ForEach(families, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .task {
                let loaded = NSFontManager.shared.availableFontFamilies.sorted {
                    $0.localizedStandardCompare($1) == .orderedAscending
                }
                families = loaded
            }
            HStack {
                Text("Size \(Int(size))")
                Slider(value: Binding(
                    get: { size },
                    set: { onChange(name, $0, weight) }
                ), in: 9...22)
            }
            HStack {
                Text(skuffFontWeightName(weight))
                Slider(value: Binding(
                    get: { weight },
                    set: { onChange(name, size, $0) }
                ), in: 0...1)
            }
        }
    }
}
