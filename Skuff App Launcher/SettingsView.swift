import AppKit
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case layout
    case theme
    case shape
    case font
    case shortcuts
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .layout: "Layout"
        case .theme: "Theme"
        case .shape: "Shape"
        case .font: "Font"
        case .shortcuts: "Shortcuts"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .layout: "rectangle.lefthalf.filled"
        case .theme: "paintpalette"
        case .shape: "square.on.square.dashed"
        case .font: "textformat"
        case .shortcuts: "keyboard"
        case .general: "gearshape"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: LibraryStore
    @State private var page: SettingsTab = .layout
    @State private var draftFinish: TabFinish = .flat
    @State private var draftTheme: ThemePreset = .pastel
    @State private var draftTemplate: ShapeTemplate = .standard
    @State private var draftSlant: Double = 8
    @State private var draftCorner: Double = 8
    @State private var draftTabWidth: Double = 34
    @State private var draftTabHeight: Double = 86
    @State private var draftOverlap: Double = 10
    @State private var draftSkew: Double = 0
    @State private var draftStaggerPattern: StaggerPattern = .none
    @State private var draftStaggerAmount: Double = 0
    @State private var draftTilt: Double = 0
    @State private var draftStaggerSeed: Int = 7
    @State private var draftJoinRadius: Double = 10
    @State private var draftConnectedTab: Bool = true
    @State private var draftTabShadow: Double = 0.5
    @State private var draftPaperEdge: Bool = true
    @State private var previewHover: Int?
    @State private var draftFontName: String?
    @State private var draftFontSize: Double = 13
    @State private var draftFontWeight: Double = 0.4
    @State private var excludedDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(SettingsTab.allCases) { tab in
                    Tab(tab.title, systemImage: tab.symbol, value: tab) {
                        pageContent(tab)
                    }
                }
            }
            .tabViewStyle(.tabBarOnly)
            .padding(.top, 14)
            Text("Built by voq.no · Copyright 2026")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .frame(minWidth: 560, idealWidth: 560, minHeight: 520, idealHeight: page == .shape ? 700 : 580)
        .onAppear { loadDrafts() }
        .onChange(of: store.settingsEpoch) { _, _ in loadDrafts() }
    }

    @ViewBuilder
    private func pageContent(_ tab: SettingsTab) -> some View {
        ScrollView {
            Form {
                switch tab {
                case .layout:
                    layoutSection
                case .theme:
                    themeSection
                case .shape:
                    shapeSection
                case .font:
                    fontSection
                case .shortcuts:
                    shortcutsSection
                case .general:
                    generalSection
                }
            }
            .formStyle(.grouped)
        }
        .overlay(alignment: .bottom) {
            if tab == .shape {
                LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var layoutSection: some View {
        Section("Edge") {
            Picker("Edge", selection: Binding(
                get: { store.settings.edge },
                set: { edge in store.updateSettings { $0.edge = edge } }
            )) {
                ForEach(ScreenEdge.allCases) { edge in
                    Text(edge.title).tag(edge)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if store.settings.edge == .bottom {
                Text("On the bottom edge, the strip matches the Dock’s width and sits just above it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Section("Open animation") {
            Picker("Open animation", selection: Binding(
                get: { store.settings.sheetMotion },
                set: { motion in store.updateSettings { $0.sheetMotion = motion } }
            )) {
                ForEach(SheetMotion.allCases) { motion in
                    Label(motion.title, systemImage: motion.symbol).tag(motion)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var themeSection: some View {
        Section("Style") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(TabFinish.allCases) { finish in
                    Button {
                        draftFinish = finish
                    } label: {
                        VStack(spacing: 6) {
                            styleChip(finish)
                            Text(finish.title)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(draftFinish == finish ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(draftFinish == finish ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        }
                        .overlay(alignment: .topTrailing) {
                            if draftFinish == finish {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(4)
                            }
                        }
                        // A plain button only hits drawn pixels; make the whole card clickable.
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            tabStripPreview(shape: liveShape, theme: draftTheme, finish: draftFinish, font: previewFont)
        }
        Section("Theme") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(ThemePreset.allCases) { theme in
                    Button {
                        if theme.isFree || store.pro.isPro {
                            draftTheme = theme
                        } else {
                            store.pro.lastError = "\(theme.title) is part of Pro."
                        }
                    } label: {
                        selectableCard(selected: draftTheme == theme) {
                            VStack(spacing: 4) {
                                HStack(spacing: 2) {
                                    ForEach(theme.palette.prefix(4), id: \.self) { hex in
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(SkuffColor(hex: hex).color)
                                            .frame(width: 12, height: 12)
                                    }
                                }
                                Text(theme.title)
                                if !theme.isFree && !store.pro.isPro {
                                    Text("Pro").font(.caption2)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .disabled(!draftFinish.usesThemeColor)
            .opacity(draftFinish.usesThemeColor ? 1 : 0.45)
            if !draftFinish.usesThemeColor {
                Text("Liquid uses the default macOS glass for tabs and folders, so theme colors are not applied.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            applyCTA("Apply theme to all tabs", help: "Use this theme and style for every tab.", action: applyThemeDraft)
        }
    }

    @ViewBuilder
    private var shapeSection: some View {
        let preview = draftShape
        Section("Shape") {
            tabStripPreview(shape: preview, theme: draftTheme, finish: draftFinish, font: previewFont)
            Text("Templates")
                .font(.subheadline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(ShapeTemplate.allCases.filter { $0 != .custom }) { template in
                    Button {
                        applyTemplate(template)
                    } label: {
                        selectableCard(selected: draftTemplate == template) {
                            VStack(spacing: 6) {
                                templatePreview(template.preset ?? preview)
                                Text(template.title)
                                if !template.isFree && !store.pro.isPro {
                                    Text("Pro").font(.caption2)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        Section {
            slider("Slant", value: preview.slant, range: 0...12) { value in
                draftTemplate = .custom
                draftSlant = value
            }
            slider("Corner radius", value: preview.cornerRadius, range: 0...16) { value in
                draftTemplate = .custom
                draftCorner = value
            }
            slider("Tab width", value: preview.tabWidth, range: 24...48) { value in
                draftTemplate = .custom
                draftTabWidth = value
            }
            slider("Tab height", value: preview.tabHeight, range: 40...140) { value in
                draftTemplate = .custom
                draftTabHeight = value
            }
            slider("Overlap", value: preview.overlap, range: 0...24) { value in
                draftTemplate = .custom
                draftOverlap = value
            }
            slider("Join radius", value: CGFloat(draftJoinRadius), range: 0...20) { value in
                draftTemplate = .custom
                draftJoinRadius = value
            }
            slider("Tab shadow", value: CGFloat(draftTabShadow), range: 0...1) { value in
                draftTabShadow = value
            }
            Toggle("Connected tab", isOn: $draftConnectedTab)
            Toggle("Paper edge", isOn: $draftPaperEdge)
        } header: {
            HStack {
                Text("Custom")
                Spacer()
                Button("Reset") { resetShapeDrafts() }
                    .buttonStyle(.borderless)
            }
        }
        Section("Stagger") {
            Picker("Pattern", selection: Binding(
                get: { draftStaggerPattern },
                set: { value in
                    draftTemplate = .custom
                    draftStaggerPattern = value
                }
            )) {
                ForEach(StaggerPattern.allCases) { pattern in
                    Text(pattern.title).tag(pattern)
                }
            }
            .pickerStyle(.menu)
            slider("Height variance", value: preview.staggerAmount, range: 0...24) { value in
                draftTemplate = .custom
                draftStaggerAmount = value
            }
            slider("Skew", value: preview.skew, range: -30...30) { value in
                draftTemplate = .custom
                draftSkew = value
            }
            slider("Tilt", value: preview.tilt, range: -6...6) { value in
                draftTemplate = .custom
                draftTilt = value
            }
            if draftStaggerPattern == .random {
                Button("Shuffle") {
                    draftTemplate = .custom
                    draftStaggerSeed = Int.random(in: 1...9_999)
                }
            }
            if !store.pro.isPro {
                Text("Shape templates and custom controls are part of Pro. The strip is using the standard shape.")
                    .font(.caption)
            }
            applyCTA("Apply to all tabs", action: applyShapeDraft)
                .disabled(!store.pro.isPro && draftTemplate != .standard)
        }
    }

    @ViewBuilder
    private var fontSection: some View {
        Section("Font") {
            tabStripPreview(shape: liveShape, theme: draftTheme, finish: draftFinish, font: previewFont)
            if store.pro.isPro {
                FontControls(
                    name: draftFontName,
                    size: draftFontSize,
                    weight: draftFontWeight
                ) { name, size, weight in
                    draftFontName = name
                    draftFontSize = size
                    draftFontWeight = weight
                }
                applyCTA("Apply to all tabs", action: applyFontDraft)
            } else {
                Text("Custom fonts are part of Pro.")
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var shortcutsSection: some View {
        Section("Shortcuts") {
            Toggle("Option-1 through Option-9 open tabs", isOn: Binding(
                get: { store.settings.shortcutsEnabled },
                set: { value in store.updateSettings { $0.shortcutsEnabled = value } }
            ))
            Text("The first nine tabs, in the order you see them.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(store.orderedTabs().prefix(9).enumerated()), id: \.element.id) { index, tab in
                shortcutRow(index: index, tab: tab)
            }
            Divider()
            Toggle("Toggle tabs while another app is full screen", isOn: Binding(
                get: { store.settings.toggleHotkeyEnabled },
                set: { value in store.updateSettings { $0.toggleHotkeyEnabled = value } }
            ))
            HStack {
                Text(store.recordingToggleHotkey
                     ? "Press a shortcut…"
                     : HotkeyCenter.display(
                        keyCode: store.settings.toggleHotkeyKeyCode,
                        carbonModifiers: store.settings.toggleHotkeyCarbonModifiers
                     ))
                    .font(.body.monospaced())
                Spacer()
                if store.failedToggleHotkey {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("This shortcut is already used by another app.")
                }
                Button(store.recordingToggleHotkey ? "Cancel" : "Change…") {
                    if store.recordingToggleHotkey {
                        store.endRecordingToggleHotkey()
                    } else {
                        store.beginRecordingToggleHotkey()
                    }
                }
            }
            Text("Default is Option-Space. Works while another app is full screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var generalSection: some View {
        Section("Full screen") {
            Picker("When an app is full screen", selection: Binding(
                get: { store.settings.fullScreenBehavior },
                set: { value in store.updateSettings { $0.fullScreenBehavior = value } }
            )) {
                ForEach(FullScreenBehavior.allCases) { behavior in
                    Text(behavior == .collapseToHandle ? "Collapse to edge handle (default)" : behavior.title)
                        .tag(behavior)
                }
            }
            Toggle("Respect menu bar and Dock", isOn: Binding(
                get: { store.settings.respectMenuBarAndDock },
                set: { value in store.updateSettings { $0.respectMenuBarAndDock = value } }
            ))
            Text("Exclusions")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(store.settings.fullScreenExclusions) { rule in
                HStack {
                    Text(exclusionName(rule.bundleID))
                        .lineLimit(1)
                    Spacer()
                    Picker("Behavior", selection: Binding(
                        get: { rule.mode },
                        set: { mode in
                            store.updateSettings { settings in
                                if let index = settings.fullScreenExclusions.firstIndex(where: { $0.bundleID == rule.bundleID }) {
                                    settings.fullScreenExclusions[index].mode = mode
                                }
                            }
                        }
                    )) {
                        ForEach(FullScreenExclusionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    Button("Remove") {
                        store.removeFullScreenExclusion(rule.bundleID)
                    }
                }
            }
            Menu("Add app") {
                ForEach(runningExclusionCandidates(), id: \.id) { app in
                    Button(app.name) {
                        store.addFullScreenExclusion(bundleID: app.id, mode: .alwaysShow)
                    }
                }
            }
        }
        Section("Pro") {
            if store.pro.isPro {
                Text("Pro is unlocked on this Mac.")
            } else {
                Text("Free includes 5 app tabs, colors, emoji, symbols, search, and shortcuts. Pro unlocks unlimited tabs, fonts, image icons, every theme, and tab shape.")
                Button(store.pro.upgradeLabel) {
                    Task { await store.pro.purchase() }
                }
            }
            Button("Restore Purchases") {
                Task { await store.pro.restore() }
            }
            if let error = store.pro.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        Section("Folder") {
            if ProFeature.folderTabs.isUnlocked(in: store) {
                Picker("Default view", selection: Binding(
                    get: { store.settings.folderViewMode },
                    set: { value in store.updateSettings { $0.folderViewMode = value } }
                )) {
                    ForEach(FolderViewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker("Default sort", selection: Binding(
                    get: { store.settings.folderSort },
                    set: { value in store.updateSettings { $0.folderSort = value } }
                )) {
                    ForEach(FolderSortKey.allCases) { key in
                        Text(key.title).tag(key)
                    }
                }
                Toggle("Newest first", isOn: Binding(
                    get: { !store.settings.folderSortAscending },
                    set: { value in store.updateSettings { $0.folderSortAscending = !value } }
                ))
                Toggle("Show hidden files", isOn: Binding(
                    get: { store.settings.folderShowHidden },
                    set: { value in store.updateSettings { $0.folderShowHidden = value } }
                ))
                Toggle("Quick Look thumbnails", isOn: Binding(
                    get: { store.settings.folderThumbnails },
                    set: { value in store.updateSettings { $0.folderThumbnails = value } }
                ))
                Text("Excluded names")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(store.settings.folderExcludedNames.enumerated()), id: \.offset) { index, name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button("Remove") {
                            store.updateSettings { $0.folderExcludedNames.remove(at: index) }
                        }
                    }
                }
                HStack {
                    TextField("Name to exclude", text: $excludedDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let name = excludedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        store.updateSettings {
                            if !$0.folderExcludedNames.contains(name) {
                                $0.folderExcludedNames.append(name)
                            }
                        }
                        excludedDraft = ""
                    }
                }
                Button("Clear thumbnail cache") {
                    IconStore.clearThumbnailCache()
                    store.ioMessage = "Thumbnail cache cleared."
                }
            } else {
                Text("Folder tabs and content search are Pro features")
                Button(store.pro.upgradeLabel) {
                    Task { await store.pro.purchase() }
                }
            }
        }
        Section("Reset") {
            Button("Restore default tabs") {
                store.confirmRestoreDefaultTabs()
            }
            Button("Reset appearance (Layout, Theme, Shape, Font)") {
                store.confirmResetAppearance()
            }
            Button("Reset everything", role: .destructive) {
                store.confirmResetEverything()
            }
        }
        Section("Configuration") {
            Button("Export…") { store.exportConfig() }
            Button("Import…") { store.importConfig() }
            if let message = store.ioMessage {
                Text(message).font(.caption)
            }
        }
    }

    private var liveShape: EffectiveShape {
        store.settings.effectiveShape(isPro: store.pro.isPro)
    }

    private var draftShape: EffectiveShape {
        EffectiveShape(
            slant: CGFloat(draftSlant),
            cornerRadius: CGFloat(draftCorner),
            tabWidth: CGFloat(draftTabWidth),
            tabHeight: CGFloat(draftTabHeight),
            overlap: CGFloat(draftOverlap),
            skew: CGFloat(draftSkew),
            staggerPattern: draftStaggerPattern,
            staggerAmount: CGFloat(draftStaggerAmount),
            tilt: CGFloat(draftTilt),
            staggerSeed: draftStaggerSeed
        )
    }

    private var previewFont: Font {
        TabMetrics.make(
            shape: draftShape,
            fontName: store.pro.isPro ? draftFontName : nil,
            fontSize: store.pro.isPro ? draftFontSize : 13,
            fontWeight: store.pro.isPro ? draftFontWeight : 0.4
        ).font
    }

    private func loadDrafts() {
        let settings = store.settings
        draftFinish = settings.tabFinish
        draftTheme = settings.theme
        draftTemplate = store.pro.isPro ? settings.shapeTemplate : .standard
        let shape = settings.effectiveShape(isPro: store.pro.isPro)
        draftSlant = Double(shape.slant)
        draftCorner = Double(shape.cornerRadius)
        draftTabWidth = Double(shape.tabWidth)
        draftTabHeight = Double(shape.tabHeight)
        draftOverlap = Double(shape.overlap)
        draftSkew = Double(shape.skew)
        draftStaggerPattern = shape.staggerPattern
        draftStaggerAmount = Double(shape.staggerAmount)
        draftTilt = Double(shape.tilt)
        draftStaggerSeed = shape.staggerSeed
        draftJoinRadius = settings.joinRadius
        draftConnectedTab = settings.connectedTab
        draftTabShadow = settings.tabShadow
        draftPaperEdge = settings.paperEdge
        draftFontName = settings.globalFontName
        draftFontSize = settings.globalFontSize
        draftFontWeight = settings.globalFontWeight
    }

    private func applyTemplate(_ template: ShapeTemplate) {
        guard template.isFree || store.pro.isPro, let preset = template.preset else {
            store.pro.lastError = "\(template.title) is part of Pro."
            return
        }
        draftTemplate = template
        draftSlant = Double(preset.slant)
        draftCorner = Double(preset.cornerRadius)
        draftTabWidth = Double(preset.tabWidth)
        draftTabHeight = Double(preset.tabHeight)
        draftOverlap = Double(preset.overlap)
        draftSkew = Double(preset.skew)
        draftStaggerPattern = preset.staggerPattern
        draftStaggerAmount = Double(preset.staggerAmount)
        draftTilt = Double(preset.tilt)
        draftStaggerSeed = preset.staggerSeed
    }

    private func resetShapeDrafts() {
        let defaults = ShapeTemplate.standard.preset ?? EffectiveShape(slant: 8, cornerRadius: 8, tabWidth: 34, tabHeight: 86, overlap: 10)
        draftTemplate = .standard
        draftSlant = Double(defaults.slant)
        draftCorner = Double(defaults.cornerRadius)
        draftTabWidth = Double(defaults.tabWidth)
        draftTabHeight = Double(defaults.tabHeight)
        draftOverlap = Double(defaults.overlap)
        draftSkew = 0
        draftStaggerPattern = .none
        draftStaggerAmount = 0
        draftTilt = 0
        draftStaggerSeed = 7
        draftJoinRadius = 10
        draftConnectedTab = true
        draftTabShadow = 0.5
        draftPaperEdge = true
    }

    private func applyThemeDraft() {
        if draftFinish != .liquid, !draftTheme.isFree, !store.pro.isPro {
            store.pro.lastError = "\(draftTheme.title) is part of Pro."
            return
        }
        store.updateSettings {
            $0.tabFinish = draftFinish
            $0.theme = draftTheme
        }
        if draftFinish != .liquid {
            store.applyTheme()
        }
    }

    private func applyShapeDraft() {
        guard store.pro.isPro || draftTemplate == .standard else {
            store.pro.lastError = "Shape templates and custom controls are part of Pro."
            return
        }
        store.updateSettings {
            $0.shapeTemplate = draftTemplate
            $0.slant = draftSlant
            $0.cornerRadius = draftCorner
            $0.tabWidth = draftTabWidth
            $0.tabHeight = draftTabHeight
            $0.overlap = draftOverlap
            $0.skew = draftSkew
            $0.staggerPattern = draftStaggerPattern
            $0.staggerAmount = draftStaggerAmount
            $0.tilt = draftTilt
            $0.staggerSeed = draftStaggerSeed
            $0.joinRadius = draftJoinRadius
            $0.connectedTab = draftConnectedTab
            $0.tabShadow = draftTabShadow
            $0.paperEdge = draftPaperEdge
        }
    }

    private func applyFontDraft() {
        guard store.pro.isPro else {
            store.pro.lastError = "Custom fonts are part of Pro."
            return
        }
        store.updateSettings {
            $0.globalFontName = draftFontName
            $0.globalFontSize = draftFontSize
            $0.globalFontWeight = draftFontWeight
        }
        store.applyFontToAllTabs()
    }

    private func exclusionName(_ bundleID: String) -> String {
        if let name = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name
        }
        return bundleID
    }

    private func runningExclusionCandidates() -> [InstalledApp] {
        let existing = Set(store.settings.fullScreenExclusions.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> InstalledApp? in
                guard let id = app.bundleIdentifier, !existing.contains(id), let url = app.bundleURL else { return nil }
                return InstalledApp(bundleID: id, name: app.localizedName ?? id, url: url, category: "")
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func shortcutRow(index: Int, tab: FolderTabRecord) -> some View {
        let failed = store.failedHotkeys.contains(index)
        let paint = SkuffColor(hex: tab.colorHex)
        return HStack(spacing: 8) {
            HStack(spacing: 3) {
                Image(systemName: "option")
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityLabel("Option \(index + 1)")
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(paint.color)
                .frame(width: 22, height: 22)
                .overlay { shortcutGlyph(tab, color: paint.textColor) }
            Text(tab.title)
                .lineLimit(1)
            Spacer(minLength: 0)
            if failed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Option-\(index + 1) is already used by another app.")
            }
        }
    }

    @ViewBuilder
    private func shortcutGlyph(_ tab: FolderTabRecord, color: Color) -> some View {
        if let emoji = tab.iconEmoji, !emoji.isEmpty {
            Text(emoji).font(.system(size: 11))
        } else if let symbol = tab.iconSymbol, !symbol.isEmpty {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
        } else {
            Image(systemName: tab.kind == .folders ? "folder" : (tab.kind == .smartFilter ? "line.3.horizontal.decrease.circle" : "square.grid.2x2"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    private func tabStripPreview(shape: EffectiveShape, theme: ThemePreset, finish: TabFinish, font: Font) -> some View {
        let names = ["Dev", "Office", "Media", "Design", "Home"]
        let palette = (theme.isFree || store.pro.isPro) ? theme.palette : ThemePreset.pastel.palette
        let colors = palette.map { SkuffColor(hex: $0).color }
        let base = max(shape.tabWidth, 28)
        let reserved = base + shape.staggerAmount + 18
        return HStack(alignment: .bottom, spacing: -shape.overlap) {
            ForEach(0..<names.count, id: \.self) { index in
                let paint = SkuffColor(hex: palette[index % palette.count])
                let active = index == 1
                let hovered = previewHover == index
                let stagger = skuffStaggerOffset(
                    index: index,
                    count: names.count,
                    pattern: shape.staggerPattern,
                    amount: shape.staggerAmount,
                    isActive: active,
                    seed: shape.staggerSeed
                )
                let height = base + stagger
                let face = TrapezoidTabShape(slant: shape.slant, cornerRadius: shape.cornerRadius, edge: .bottom, skew: shape.skew)
                let width = max(72, min(104, shape.tabHeight * 0.7)) + skuffSkewPadding(skew: shape.skew, thickness: height)
                ZStack {
                    TabBackground(
                        style: finish,
                        face: face,
                        paint: paint,
                        palette: colors,
                        locked: false,
                        isActive: active,
                        isHovered: hovered,
                        reduceMotion: false,
                        edge: .bottom
                    )
                    Text(names[index])
                        .font(font)
                        .foregroundStyle(skuffTabInk(finish: finish, paint: paint))
                        .lineLimit(1)
                        .transformEffect(CGAffineTransform(a: 1, b: 0, c: tan(min(max(shape.skew, -30), 30) * .pi / 180) * 0.5, d: 1, tx: 0, ty: 0))
                }
                .frame(width: width, height: height)
                .contentShape(face)
                .rotationEffect(.degrees(index % 2 == 0 ? shape.tilt : -shape.tilt), anchor: .bottom)
                .onHover { inside in
                    previewHover = inside ? index : (previewHover == index ? nil : previewHover)
                }
            }
        }
        .background(alignment: .bottom) {
            if draftConnectedTab {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SkuffColor(hex: palette[1 % palette.count]).color.opacity(0.78))
                    .frame(height: 40)
                    .offset(y: 6)
            }
        }
        .padding(.bottom, draftConnectedTab ? 34 : 0)
        .frame(height: reserved + (draftConnectedTab ? 34 : 0))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .accessibilityHidden(true)
    }

    private func templatePreview(_ shape: EffectiveShape) -> some View {
        let count = 4
        let base: CGFloat = 18
        return HStack(alignment: .bottom, spacing: -min(shape.overlap, 8)) {
            ForEach(0..<count, id: \.self) { index in
                let stagger = skuffStaggerOffset(
                    index: index,
                    count: count,
                    pattern: shape.staggerPattern,
                    amount: min(shape.staggerAmount, 10),
                    isActive: index == 1,
                    seed: shape.staggerSeed
                )
                TrapezoidTabShape(slant: shape.slant, cornerRadius: min(shape.cornerRadius, 8), edge: .bottom, skew: shape.skew * 0.6)
                    .fill(Color.accentColor.opacity(0.35 + Double(index) * 0.14))
                    .frame(width: 18, height: base + stagger)
                    .rotationEffect(.degrees(index % 2 == 0 ? shape.tilt : -shape.tilt), anchor: .bottom)
            }
        }
        .frame(height: 32)
        .accessibilityHidden(true)
    }

    private func styleChip(_ finish: TabFinish) -> some View {
        let paint = SkuffColor(hex: draftTheme.palette.first ?? "F6C6CE")
        let face = TrapezoidTabShape(slant: 6, cornerRadius: 6, edge: .bottom)
        return TabBackground(
            style: finish,
            face: face,
            paint: paint,
            palette: draftTheme.palette.map { SkuffColor(hex: $0).color },
            locked: false,
            isActive: true,
            isHovered: false,
            reduceMotion: true,
            edge: .bottom
        )
        .frame(width: 44, height: 22)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func selectableCard<Content: View>(selected: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                        .padding(3)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 0.5)
            }
            // A plain button only hits drawn pixels; make the whole card clickable.
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func applyCTA(_ title: String, help: String? = nil, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .help(help ?? title)
    }

    private func slider(_ title: String, value: CGFloat, range: ClosedRange<CGFloat>, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 110, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { set($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound)
            )
            .disabled(!store.pro.isPro)
            Text("\(Int(value.rounded()))")
                .font(.body.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
        .frame(height: 32)
    }
}
