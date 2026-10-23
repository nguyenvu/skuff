import AppKit
import os
import SwiftUI
import UniformTypeIdentifiers

struct FramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct SizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 1, next.height > 1 {
            value = next
        }
    }
}

struct ControlFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1, next.height > 1 {
            value = next
        }
    }
}

struct TabStackSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 1, next.height > 1 {
            value = next
        }
    }
}

struct EdgeStripView: View {
    @ObservedObject var store: LibraryStore
    var screenID: String
    var onFrames: ([UUID: CGRect]) -> Void
    var onControlFrame: (CGRect) -> Void
    var onTabStackSize: (CGSize) -> Void
    var onContentSize: (CGSize) -> Void

    @State private var hovered: UUID?
    @State private var dropTarget: UUID?
    @State private var dragID: UUID?
    /// Tab order while a tab is being dragged; written to the store once, on release.
    @State private var previewOrder: [UUID]?
    @State private var dragTranslation: CGFloat = 0
    /// How far the dragged tab's own slot has moved through swaps, so it stays under the pointer.
    @State private var dragShift: CGFloat = 0
    @State private var frames: [UUID: CGRect] = [:]
    @State private var gripOrigin: Double = 0
    @State private var gripStartMouse: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = store.screenGeneration
        let edge = store.settings.edge
        let shape = store.settings.effectiveShape(isPro: store.pro.isPro)
        let ordered = previewOrdered(store.orderedTabs())
        let dockWidth = bottomDockWidth()
        let budget = stripBudget(edge: edge, dockWidth: dockWidth)
        let floors = ordered.map { titleFloor($0, edge: edge, shape: shape) }
        let layout = TabStripLayout.make(
            tabs: ordered.map { ($0.id, $0.title) },
            budget: budget,
            baseOverlap: shape.overlap,
            activeIDs: [],
            fill: edge == .bottom && dockWidth != nil,
            full: max(shape.tabHeight, TabStripLayout.minLength),
            floors: floors
        )
        return strip(ordered: ordered, layout: layout, edge: edge, shape: shape)
            .overlay(alignment: .bottom) { undoToast }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                store.acceptDrop(providers, onto: nil)
                return true
            }
            .padding(edgePadding(edge))
            .coordinateSpace(name: "strip")
            .fixedSize()
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: SizeKey.self, value: geo.size)
                }
            )
            .onPreferenceChange(FramesKey.self) { value in
                frames = value
                onFrames(value)
            }
            .onPreferenceChange(ControlFrameKey.self, perform: onControlFrame)
            .onPreferenceChange(TabStackSizeKey.self, perform: onTabStackSize)
            .onPreferenceChange(SizeKey.self, perform: onContentSize)
            .onAppear { gripOrigin = store.anchor(for: screenID).offset }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: layout)
    }

    private func previewOrdered(_ tabs: [FolderTabRecord]) -> [FolderTabRecord] {
        guard let previewOrder else { return tabs }
        let byID = Dictionary(tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let result = previewOrder.compactMap { byID[$0] }
        return result.count == tabs.count ? result : tabs
    }

    /// Gap between stacked tabs; negative because tabs overlap.
    private func stackSpacing(_ layout: TabStripLayout, shape: EffectiveShape) -> CGFloat {
        -max(layout.overlap, shape.slant + 2)
    }

    private func stripBudget(edge: ScreenEdge, dockWidth: CGFloat?) -> CGFloat {
        if edge == .bottom, let dockWidth {
            return max(160, dockWidth - 24)
        }
        return screenLength(edge) - 88
    }

    private func titleFloor(_ tab: FolderTabRecord, edge: ScreenEdge, shape: EffectiveShape) -> CGFloat {
        let metrics = TabMetrics.make(settings: store.settings, isPro: store.pro.isPro)
        return max(metrics.fittedLength(for: tab.title, horizontal: edge.runsAlongX), metrics.tabHeight)
    }

    private func bottomDockWidth() -> CGFloat? {
        guard store.settings.edge == .bottom,
              let screen = NSScreen.screens.first(where: { $0.skuffID == screenID }),
              let dock = DockMetrics.bottomDock(on: screen) else { return nil }
        return dock.width
    }

    private func screenLength(_ edge: ScreenEdge) -> CGFloat {
        guard let screen = NSScreen.screens.first(where: { $0.skuffID == screenID }) else { return 800 }
        return edge.runsAlongX ? screen.frame.width : screen.frame.height
    }

    /// Padding at both ends of the strip, along the edge. `PanelController` uses it to
    /// center the tabs themselves rather than tabs plus the grip and + button.
    static let bleed: CGFloat = 12

    private func edgePadding(_ edge: ScreenEdge) -> EdgeInsets {
        let bleed = Self.bleed
        let peekRoom: CGFloat = 64
        switch edge {
        case .right:
            return EdgeInsets(top: bleed, leading: bleed + peekRoom, bottom: bleed, trailing: 0)
        case .left:
            return EdgeInsets(top: bleed, leading: 0, bottom: bleed, trailing: bleed + peekRoom)
        case .top:
            return EdgeInsets(top: 0, leading: bleed, bottom: bleed + peekRoom, trailing: bleed)
        case .bottom:
            return EdgeInsets(top: bleed + peekRoom, leading: bleed, bottom: 0, trailing: bleed)
        }
    }

    @ViewBuilder
    private func strip(ordered: [FolderTabRecord], layout: TabStripLayout, edge: ScreenEdge, shape: EffectiveShape) -> some View {
        let overlap = stackSpacing(layout, shape: shape)
        let tabs = ForEach(Array(ordered.enumerated()), id: \.element.id) { index, tab in
            let item = layout.items.first { $0.id == tab.id }
            tabRow(tab: tab, item: item, index: index, count: ordered.count, edge: edge, shape: shape, spacing: overlap)
        }
        let controls = controlCluster(edge: edge)
        switch edge {
        case .left:
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: overlap) { tabs }
                    .background { tabStackProbe() }
                controls
            }
        case .right:
            VStack(alignment: .trailing, spacing: 6) {
                VStack(alignment: .trailing, spacing: overlap) { tabs }
                    .background { tabStackProbe() }
                controls
            }
        case .top:
            HStack(alignment: .top, spacing: 6) {
                HStack(alignment: .top, spacing: overlap) { tabs }
                    .background { tabStackProbe() }
                controls
            }
        case .bottom:
            HStack(alignment: .bottom, spacing: 6) {
                HStack(alignment: .bottom, spacing: overlap) { tabs }
                    .background { tabStackProbe() }
                controls
            }
        }
    }

    private func tabStackProbe() -> some View {
        GeometryReader { geo in
            Color.clear.preference(key: TabStackSizeKey.self, value: geo.size)
        }
    }

    private func tabRow(
        tab: FolderTabRecord,
        item: TabStripLayout.Item?,
        index: Int,
        count: Int,
        edge: ScreenEdge,
        shape: EffectiveShape,
        spacing: CGFloat
    ) -> some View {
        let length = item?.length ?? TabStripLayout.fullLength
        let isHover = hovered == tab.id
        let isOpen = store.openTabID == tab.id
        let isDragged = dragID == tab.id
        let showPeek = isHover && !isOpen && dragID == nil && !tab.appBundleIDs.isEmpty
        return tabBody(tab: tab, length: length, edge: edge, shape: shape, spacing: spacing, isHover: isHover, isOpen: isOpen, index: index, count: max(count, 1))
            .overlay(alignment: peekAnchor(edge)) {
                if showPeek {
                    peek(tab)
                        .fixedSize()
                        .offset(peekOffset(edge, shown: shape.tabWidth))
                        .allowsHitTesting(false)
                }
            }
            .offset(dragOffset(tab: tab, edge: edge))
            // The dragged tab follows the pointer exactly; only its neighbours animate.
            .transaction { if isDragged { $0.animation = nil } }
            .zIndex(isDragged ? 110 : (isOpen ? 100 : (isHover ? 90 : Double(index))))
            .fixedSize(horizontal: !edge.runsAlongX, vertical: edge.runsAlongX)
    }

    private func peekAnchor(_ edge: ScreenEdge) -> Alignment {
        switch edge {
        case .left: .leading
        case .right: .trailing
        case .top: .top
        case .bottom: .bottom
        }
    }

    private func peekOffset(_ edge: ScreenEdge, shown: CGFloat) -> CGSize {
        let gap = shown + 8
        return switch edge {
        case .left: CGSize(width: gap, height: 0)
        case .right: CGSize(width: -gap, height: 0)
        case .top: CGSize(width: 0, height: gap)
        case .bottom: CGSize(width: 0, height: -gap)
        }
    }

    private func tabBody(
        tab: FolderTabRecord,
        length: CGFloat,
        edge: ScreenEdge,
        shape: EffectiveShape,
        spacing: CGFloat,
        isHover: Bool,
        isOpen: Bool,
        index: Int,
        count: Int
    ) -> some View {
        let locked = store.isBeyondFreeLimit(tab)
        let metrics = TabMetrics.make(settings: store.settings, isPro: store.pro.isPro)
        let reach = metrics.protrusion
        let stagger = skuffStaggerOffset(
            index: index,
            count: count,
            pattern: shape.staggerPattern,
            amount: shape.staggerAmount,
            isActive: isOpen,
            seed: shape.staggerSeed
        )
        let connected = store.settings.connectedTab && store.openTabID != nil
        let idleShort: CGFloat = connected && !isOpen ? 10 : 0
        let thickness = shape.tabWidth - idleShort + stagger + (isOpen && !connected ? reach : 0)
        let slot = shape.tabWidth + reach + shape.staggerAmount
        let skewPad = skuffSkewPadding(skew: shape.skew, thickness: thickness)
        let paint = connected && !isOpen ? SkuffColor(hex: tab.colorHex).dimmed() : SkuffColor(hex: tab.colorHex)
        let title = tab.title
        let horizontal = edge.runsAlongX
        let face = TrapezoidTabShape(slant: shape.slant, cornerRadius: shape.cornerRadius, edge: edge, skew: shape.skew)
        let along = (horizontal ? length : thickness) + skewPad
        let height: CGFloat = horizontal ? thickness : length + skewPad
        let labels = TabFaceLabel(
            title: title,
            icon: tab.icon,
            locked: locked,
            metrics: metrics,
            ink: skuffTabInk(finish: store.settings.tabFinish, paint: paint),
            horizontal: horizontal,
            maxAlong: length
        )
        .transformEffect(labelUnskew(edge, skew: shape.skew))
        .frame(maxWidth: horizontal ? nil : .infinity, maxHeight: .infinity)
        .frame(
            minWidth: horizontal ? along : thickness,
            idealWidth: horizontal ? nil : thickness,
            maxWidth: horizontal ? nil : thickness,
            minHeight: height,
            maxHeight: height
        )
        let openIndex = store.orderedTabs().firstIndex { $0.id == store.openTabID }
        let contact = connected && !isOpen && openIndex.map { abs($0 - index) == 1 } == true
        return finishedTab(labels: labels, face: face, paint: paint, locked: locked, edge: edge, isHover: isHover, isOpen: isOpen)
            .rotationEffect(
                .degrees(index % 2 == 0 ? shape.tilt : -shape.tilt),
                anchor: skuffTiltAnchor(edge)
            )
            .shadow(
                color: Color.black.opacity(contact ? 0.22 : 0),
                radius: contact ? 4 : 0,
                x: 0,
                y: contact ? 2 : 0
            )
            .opacity(connected && isOpen ? 0 : 1)
            .allowsHitTesting(!(connected && isOpen))
            .contentShape(face)
            .overlay {
                if dropTarget == tab.id {
                    face.stroke(Color.white.opacity(0.9), lineWidth: 2)
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: FramesKey.self, value: [tab.id: geo.frame(in: .named("strip"))])
                }
            )
            .onHover { inside in
            hovered = inside ? tab.id : (hovered == tab.id ? nil : hovered)
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .gesture(tabGesture(tab: tab, edge: edge, spacing: spacing))
        .onDrop(of: [.fileURL], isTargeted: dropBinding(tab.id)) { providers in
            store.acceptDrop(providers, onto: tab.id)
            return true
        }
        .contextMenu { tabMenu(tab) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(tab, locked: locked))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(locked ? "Shows Pro." : "Shows the apps in this tab.")
        .accessibilityAction { store.toggleTab(tab.id, on: screenID) }
        .accessibilityAction(named: Text("Move earlier")) { store.moveTab(tab.id, by: -1) }
        .accessibilityAction(named: Text("Move later")) { store.moveTab(tab.id, by: 1) }
        .frame(
            width: horizontal ? nil : slot,
            height: horizontal ? slot : nil,
            alignment: screenEdgeAlignment(edge)
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHover)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isOpen)
    }

    /// The long edge stays on the screen. Extra width grows inward, into the reserved slot.
    private func screenEdgeAlignment(_ edge: ScreenEdge) -> Alignment {
        switch edge {
        case .left: .leading
        case .right: .trailing
        case .top: .top
        case .bottom: .bottom
        }
    }

    @ViewBuilder
    private var undoToast: some View {
        if let banner = store.undoBanner {
            HStack(spacing: 8) {
                Text(banner.message)
                    .font(.caption)
                    .lineLimit(1)
                if banner.canUndo {
                    Button("Undo") { store.undoLastBackup() }
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(6)
        }
    }

    private func labelUnskew(_ edge: ScreenEdge, skew: CGFloat) -> CGAffineTransform {
        let k = tan(min(max(skew, -30), 30) * .pi / 180) * 0.5
        return switch edge {
        case .bottom: CGAffineTransform(a: 1, b: 0, c: k, d: 1, tx: 0, ty: 0)
        case .top: CGAffineTransform(a: 1, b: 0, c: -k, d: 1, tx: 0, ty: 0)
        case .left: CGAffineTransform(a: 1, b: k, c: 0, d: 1, tx: 0, ty: 0)
        case .right: CGAffineTransform(a: 1, b: -k, c: 0, d: 1, tx: 0, ty: 0)
        }
    }

    @ViewBuilder
    private func finishedTab(
        labels: some View,
        face: TrapezoidTabShape,
        paint: SkuffColor,
        locked: Bool,
        edge: ScreenEdge,
        isHover: Bool,
        isOpen: Bool
    ) -> some View {
        let palette = store.settings.theme.palette.map { SkuffColor(hex: $0).color }
        labels
            .background {
                TabBackground(
                    style: store.settings.tabFinish,
                    face: face,
                    paint: paint,
                    palette: palette,
                    locked: locked,
                    isActive: isOpen,
                    isHovered: isHover,
                    reduceMotion: reduceMotion,
                    edge: edge
                )
            }
    }

    private func peek(_ tab: FolderTabRecord) -> some View {
        let ids = Array(tab.appBundleIDs.prefix(4))
        return HStack(spacing: -6) {
            ForEach(Array(ids.enumerated()), id: \.element) { index, bundleID in
                Image(nsImage: store.icon(for: bundleID))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(reduceMotion ? 0 : Double(index) * 7 - 8))
            }
        }
        .padding(4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func controlCluster(edge: ScreenEdge) -> some View {
        let grip = Image(systemName: "line.3.horizontal")
            .font(.system(size: 9, weight: .bold))
            .rotationEffect(edge.runsAlongX ? .degrees(0) : .degrees(90))
            .frame(width: 18, height: 12)
            .foregroundStyle(.secondary)
            .gesture(
                // The window moves with the strip, so measure in screen points rather than
                // in view coordinates, which would shift under the pointer.
                DragGesture(minimumDistance: 3)
                    .onChanged { _ in
                        let mouse = NSEvent.mouseLocation
                        if gripStartMouse == nil {
                            gripStartMouse = mouse
                            gripOrigin = store.anchor(for: screenID).offset
                        }
                        guard let start = gripStartMouse else { return }
                        let delta = edge.runsAlongX ? mouse.x - start.x : mouse.y - start.y
                        store.setOffset(gripOrigin + delta, for: screenID, persist: false)
                    }
                    .onEnded { _ in
                        gripStartMouse = nil
                        store.setOffset(store.anchor(for: screenID).offset, for: screenID, notify: false)
                        gripOrigin = store.anchor(for: screenID).offset
                    }
            )
            .accessibilityLabel("Move the tab strip")
        let plus = circleButton("plus", label: "Add tab", action: store.addTab)
        let settings = circleButton("gearshape", label: "Settings", action: store.showSettings)
            .help("Settings")
        // Order from the tabs outward: Settings, grip, +.
        return Group {
            if edge.runsAlongX {
                HStack(spacing: 4) { settings; grip; plus }
            } else {
                VStack(spacing: 4) { settings; grip; plus }
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: ControlFrameKey.self, value: geo.frame(in: .named("strip")))
            }
        }
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func dropBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { dropTarget == id },
            set: { targeted in
                if targeted {
                    dropTarget = id
                } else if dropTarget == id {
                    dropTarget = nil
                }
            }
        )
    }

    private func dragOffset(tab: FolderTabRecord, edge: ScreenEdge) -> CGSize {
        guard dragID == tab.id else { return .zero }
        let along = dragTranslation - dragShift
        return edge.runsAlongX ? CGSize(width: along, height: 0) : CGSize(width: 0, height: along)
    }

    /// Distance the dragged tab's slot moves when it trades places with `id`.
    private func pitch(of id: UUID, edge: ScreenEdge, spacing: CGFloat) -> CGFloat? {
        guard let frame = frames[id] else { return nil }
        let extent = edge.runsAlongX ? frame.width : frame.height
        return max(1, extent + spacing)
    }

    /// Pointer travel below which a press counts as a click rather than a drag.
    private static let clickSlop: CGFloat = 8

    /// One gesture for click and drag. Separate tap and drag gestures dropped clicks where
    /// the pointer moved a few points: too far for the tap, not far enough for the drag.
    private func tabGesture(tab: FolderTabRecord, edge: ScreenEdge, spacing: CGFloat) -> some Gesture {
        // Window coordinates: the tab itself moves while dragging, the strip window does not.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                #if DEBUG
                if value.translation == .zero {
                    Logger.input.info("tab press \(tab.title, privacy: .public) at=(\(Int(value.startLocation.x)),\(Int(value.startLocation.y)))")
                }
                #endif
                if dragID != tab.id {
                    let travel = hypot(value.translation.width, value.translation.height)
                    guard travel >= Self.clickSlop else { return }
                    dragID = tab.id
                    dragShift = 0
                    previewOrder = store.orderedTabs().map(\.id)
                }
                dragTranslation = edge.runsAlongX ? value.translation.width : value.translation.height
                guard var order = previewOrder, var index = order.firstIndex(of: tab.id) else { return }
                var shift = dragShift
                var moved = false
                // Swap once the tab is halfway across a neighbour.
                while index + 1 < order.count,
                      let step = pitch(of: order[index + 1], edge: edge, spacing: spacing),
                      dragTranslation - shift > step / 2 {
                    order.swapAt(index, index + 1)
                    index += 1
                    shift += step
                    moved = true
                }
                while index > 0,
                      let step = pitch(of: order[index - 1], edge: edge, spacing: spacing),
                      dragTranslation - shift < -step / 2 {
                    order.swapAt(index, index - 1)
                    index -= 1
                    shift -= step
                    moved = true
                }
                guard moved else { return }
                dragShift = shift
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    previewOrder = order
                }
            }
            .onEnded { value in
                #if DEBUG
                let travel = hypot(value.translation.width, value.translation.height)
                Logger.input.info("tab release \(tab.title, privacy: .public) travel=\(Int(travel)) as=\(dragID == tab.id ? "drag" : "click", privacy: .public)")
                #endif
                guard dragID == tab.id else {
                    store.toggleTab(tab.id, on: screenID)
                    return
                }
                let order = previewOrder
                previewOrder = nil
                if let order { store.applyOrder(order) }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    dragID = nil
                    dragTranslation = 0
                    dragShift = 0
                }
            }
    }

    @ViewBuilder
    private func tabMenu(_ tab: FolderTabRecord) -> some View {
        Button("Edit Tab…") { store.editTab(tab.id) }
        Button(tab.isPinned ? "Unpin" : "Pin") { store.togglePin(tab.id) }
        Button("Move Earlier") { store.moveTab(tab.id, by: -1) }
        Button("Move Later") { store.moveTab(tab.id, by: 1) }
        Button("Settings…") { store.showSettings() }
        Button("Restore Default Tabs…") { store.confirmRestoreDefaultTabs() }
        Divider()
        Button("Delete Tab") { store.requestDeleteTab(tab.id) }
        Divider()
        Button("Quit Skuff") { NSApp.terminate(nil) }
    }

    private func accessibilityLabel(_ tab: FolderTabRecord, locked: Bool) -> String {
        var parts = [tab.title, skuffItemCount(tab.appBundleIDs.count)]
        switch tab.kind {
        case .apps: parts.append("app tab")
        case .folders: parts.append("folder tab")
        case .smartFilter: parts.append("smart filter tab")
        }
        if store.tabContainsRunningApp(tab) { parts.append("contains running apps") }
        if tab.isPinned { parts.append("pinned") }
        if locked { parts.append("locked") }
        return parts.joined(separator: ", ")
    }
}

