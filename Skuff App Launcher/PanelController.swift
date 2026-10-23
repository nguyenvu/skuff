import AppKit
import ApplicationServices
import Darwin
import os
import SwiftUI

final class PassThroughPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FolderPanel: NSPanel {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

final class ShapedHostingView<Content: View>: NSHostingView<Content> {
    var hitPath: CGPath?

    /// Skuff is rarely the active app, so the first click must act, not just focus the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let hitPath, !hitPath.contains(point) { return nil }
        return super.hitTest(point)
    }
}

/// Holds the folder content with room around it for its shadow. Clicks in that margin
/// fall through instead of being swallowed by the panel.
final class SheetContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    var interactiveRects: [CGRect] = []

    /// Skuff is rarely the active app, so the first click must act, not just focus the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return super.hitTest(point) }
        if interactiveRects.isEmpty { return super.hitTest(point) }
        let local = convert(point, from: superview)
        let inside = interactiveRects.contains(where: { $0.contains(local) })
        let result = inside ? super.hitTest(point) : nil
        #if DEBUG
        if NSApp.currentEvent?.type == .leftMouseDown {
            let target = result.map { String(describing: type(of: $0)) } ?? "nil (passes through)"
            Logger.input.info("strip down local=(\(Int(local.x)),\(Int(local.y))) size=\(Int(self.bounds.width))x\(Int(self.bounds.height)) flipped=\(self.isFlipped) inRects=\(inside) key=\(self.window?.isKeyWindow ?? false) appActive=\(NSApp.isActive) target=\(target, privacy: .public)")
        }
        #endif
        return result
    }
}

@MainActor
final class PanelController: NSObject {
    private let store: LibraryStore
    private var strips: [String: StripWindow] = [:]
    private var mouseMonitor: Any?
    private var moveMonitor: Any?
    private var localMoveMonitor: Any?
    private var keyMonitor: Any?
    private var screenToken: NSObjectProtocol?
    private var spaceToken: NSObjectProtocol?
    private var activateToken: NSObjectProtocol?
    private var windowToken: NSObjectProtocol?
    private var relayoutWork: DispatchWorkItem?
    private var inLayout = false
    private var presentedTabID: UUID?
    private var hoverExpanded: Set<String> = []
    private var coveredScreens: Set<String> = []
    private var collapseTasks: [String: Task<Void, Never>] = [:]
    private var lastChrome: [String: StripChrome] = [:]
    /// Folder heights fitted to their content, by tab. Kept for the session so a tab
    /// reopens at its size instead of starting tall and shrinking.
    private var fittedSheetHeights: [UUID: CGFloat] = [:]
    private var shownSheetHeight: (id: UUID, height: CGFloat)?

    init(store: LibraryStore) {
        self.store = store
    }

    func start() {
        #if DEBUG
        GeometrySafetyTests.testDegenerateRects()
        #endif
        store.onSheetSlack = { [weak self] id, slack in
            self?.fitSheet(id, slack: slack)
        }
        screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor in controller.scheduleRelayout(reason: "screen-parameters") }
        }
        spaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor in controller.scheduleRelayout(reason: "active-space") }
        }
        activateToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor in controller.scheduleRelayout(reason: "app-activate") }
        }
        windowToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow, let controller = self else { return }
            Task { @MainActor in controller.noteWindowScreenChange(window) }
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            let point = NSEvent.mouseLocation
            guard let controller = self else { return }
            Task { @MainActor in controller.closeIfClickIsOutside(point) }
        }
        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor in controller.handleMouseMoved() }
        }
        localMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            guard let controller = self else { return event }
            Task { @MainActor in controller.handleMouseMoved() }
            return event
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let controller = self, controller.store.openTabID != nil else { return event }
            Task { @MainActor in controller.closeFolderFromKey() }
            return nil
        }
        refresh()
    }

    func togglePanel() {
        if store.tabsManuallyHidden {
            bringTabsBack()
            return
        }
        let mouseScreen = screenMatchingMouse()?.skuffID
        if let mouseScreen, chrome(for: mouseScreen) == .collapsed {
            expand(mouseScreen, reason: "hotkey")
            return
        }
        store.tabsManuallyHidden = true
        store.closeFolder()
        Logger.spaces.info("hide tabs (toggle)")
        refresh()
    }

    func bringTabsBack() {
        store.tabsManuallyHidden = false
        hoverExpanded = Set(strips.keys)
        for (id, strip) in strips {
            if !NSScreen.screens.contains(where: { $0.frame.intersects(strip.panel.frame) }) {
                Logger.spaces.info("reset off-screen strip \(id, privacy: .public)")
                store.setOffset(0, for: id, notify: false)
            }
        }
        Logger.spaces.info("bring tabs back")
        refresh()
        for strip in strips.values where strip.panel.isVisible {
            strip.panel.orderFrontRegardless()
        }
    }

    func tabsAreVisible() -> Bool {
        !store.tabsManuallyHidden && strips.values.contains(where: \.panel.isVisible)
    }

    func closeFolderFromKey() {
        store.closeFolder()
    }

    func refresh() {
        updateFullscreenCoverage()
        syncStrips()
        for strip in strips.values {
            layout(strip)
        }
        publishCollapsedScreens()
        syncSheet(animated: true)
    }

    private func syncStrips() {
        let screens = NSScreen.screens
        let ids = Set(screens.map(\.skuffID))
        for id in strips.keys where !ids.contains(id) {
            strips[id]?.panel.orderOut(nil)
            strips[id]?.sheet.orderOut(nil)
            strips[id] = nil
        }
        if let open = store.openScreenID, strips[open] == nil, !ids.contains(open) {
            store.closeFolder()
        }
        for screen in screens where strips[screen.skuffID] == nil {
            strips[screen.skuffID] = makeStrip(screenID: screen.skuffID)
        }
    }

    private func makeStrip(screenID: String) -> StripWindow {
        let panel = PassThroughPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(panel, isSheet: false)
        let hosting = PassThroughHostingView(rootView: EdgeStripView(
            store: store,
            screenID: screenID,
            onFrames: { [weak self] frames in
                self?.updateFrames(frames, screenID: screenID)
            },
            onControlFrame: { [weak self] rect in
                self?.updateControl(rect, screenID: screenID)
            },
            onTabStackSize: { [weak self] size in
                self?.updateTabStack(size, screenID: screenID)
            },
            onContentSize: { [weak self] size in
                self?.updateSize(size, screenID: screenID)
            }
        ))
        hosting.wantsLayer = true
        hosting.clipsToBounds = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting

        let sheet = FolderPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(sheet, isSheet: true)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: sheet,
            queue: .main
        ) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor in
                controller.liftStrips()
                controller.store.requestSearchFocus()
            }
        }
        let sheetHost = ShapedHostingView(rootView: FolderSheetContainer(store: store))
        sheetHost.wantsLayer = true
        sheetHost.clipsToBounds = false
        sheetHost.layer?.backgroundColor = NSColor.clear.cgColor
        let container = SheetContainerView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(sheetHost)
        sheet.contentView = container
        return StripWindow(screenID: screenID, panel: panel, hosting: hosting, sheet: sheet, sheetHost: sheetHost)
    }

    private func configure(_ panel: NSPanel, isSheet: Bool) {
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + (isSheet ? 0 : 2))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = isSheet
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        panel.isRestorable = false
    }

    private func updateSize(_ size: CGSize, screenID: String) {
        guard !inLayout, let strip = strips[screenID] else { return }
        guard size.width > 1, size.height > 1 else { return }
        guard abs(strip.contentSize.width - size.width) > 0.5 || abs(strip.contentSize.height - size.height) > 0.5 else { return }
        strip.contentSize = size
        inLayout = true
        layout(strip)
        syncSheet(animated: false)
        inLayout = false
    }

    private func updateFrames(_ frames: [UUID: CGRect], screenID: String) {
        guard let strip = strips[screenID] else { return }
        guard strip.frames != frames else { return }
        strip.frames = frames
        applyInteractive(strip)
        if store.openScreenID == screenID {
            syncSheet(animated: false)
        }
    }

    private func updateControl(_ rect: CGRect, screenID: String) {
        guard let strip = strips[screenID] else { return }
        guard strip.controlRect != rect else { return }
        strip.controlRect = rect
        applyInteractive(strip)
    }

    private func updateTabStack(_ size: CGSize, screenID: String) {
        guard let strip = strips[screenID] else { return }
        guard abs(strip.tabStackSize.width - size.width) > 0.5 || abs(strip.tabStackSize.height - size.height) > 0.5 else { return }
        strip.tabStackSize = size
        // Every edge centers on the tab stack, so its size always moves the strip.
        guard !inLayout else { return }
        inLayout = true
        layout(strip)
        inLayout = false
    }

    private func applyInteractive(_ strip: StripWindow) {
        var rects = Array(strip.frames.values)
        if strip.controlRect.width > 1, strip.controlRect.height > 1 {
            rects.append(strip.controlRect)
        }
        strip.hosting.interactiveRects = rects.map { $0.insetBy(dx: -8, dy: -8) }
    }

    private func layout(_ strip: StripWindow) {
        guard let screen = screenMatching(id: strip.screenID) else {
            Logger.spaces.info("no screen for \(strip.screenID, privacy: .public); ordering out")
            strip.panel.orderOut(nil)
            strip.sheet.orderOut(nil)
            return
        }
        let chrome = chrome(for: strip.screenID)
        publishCollapsedScreens()
        if chrome == .hidden {
            Logger.spaces.info("hide \(strip.screenID, privacy: .public)")
            if strip.panel.isVisible { strip.panel.orderOut(nil) }
            if strip.sheet.isVisible {
                strip.sheet.allowsKey = false
                strip.sheet.orderOut(nil)
            }
            lastChrome[strip.screenID] = chrome
            return
        }
        let dock = dockingRect(for: screen)
        guard GeometrySafety.isUsable(dock) else { return }
        let edge = store.settings.edge
        let shape = store.settings.effectiveShape(isPro: store.pro.isPro)
        let fallback = edge.runsAlongX
            ? CGSize(width: 280, height: shape.tabWidth + 24)
            : CGSize(width: 160, height: shape.tabWidth + 24)
        let size = GeometrySafety.sanitizedSize(strip.contentSize, fallback: fallback)
        let stored = store.anchor(for: strip.screenID).offset
        let span = edge.runsAlongX ? dock.width : dock.height
        let contentSpan = edge.runsAlongX ? size.width : size.height
        let limit = max(0, (span - contentSpan) / 2 - 4)
        let offset = GeometrySafety.clamp(CGFloat(stored), min: -limit, max: limit)
        if abs(offset - stored) > 0.5 {
            let screenID = strip.screenID
            DispatchQueue.main.async {
                self.store.setOffset(Double(offset), for: screenID, notify: false)
            }
        }
        // Center the tab stack itself; the grip and + button hang off its far end.
        // Before the stack has been measured, center the whole strip.
        let bleed = EdgeStripView.bleed
        let tabs = strip.tabStackSize
        let minY = dock.minY
        let maxY = max(dock.minY, dock.maxY - size.height)
        let minX = dock.minX
        let maxX = max(dock.minX, dock.maxX - size.width)
        func verticalOrigin() -> CGFloat {
            let centered = tabs.height > 1
                ? dock.midY + offset - size.height + bleed + tabs.height / 2
                : dock.midY - size.height / 2 + offset
            return min(max(centered, minY), maxY)
        }
        func horizontalOrigin(around midX: CGFloat) -> CGFloat {
            let centered = tabs.width > 1
                ? midX + offset - bleed - tabs.width / 2
                : midX - size.width / 2 + offset
            return min(max(centered, minX), maxX)
        }
        var frame: CGRect
        switch edge {
        case .right:
            frame = CGRect(x: dock.maxX - size.width, y: verticalOrigin(), width: size.width, height: size.height)
        case .left:
            frame = CGRect(x: dock.minX, y: verticalOrigin(), width: size.width, height: size.height)
        case .bottom:
            // Above the Dock, line up with the Dock rather than the screen.
            let dockBar = store.settings.respectMenuBarAndDock ? DockMetrics.bottomDock(on: screen) : nil
            let x = horizontalOrigin(around: dockBar?.midX ?? dock.midX)
            frame = CGRect(x: x, y: dock.minY, width: size.width, height: size.height)
        case .top:
            frame = CGRect(x: horizontalOrigin(around: dock.midX), y: dock.maxY - size.height, width: size.width, height: size.height)
        }
        if !GeometrySafety.isUsable(frame) || !screen.frame.intersects(frame) {
            Logger.spaces.info("reset off-screen frame \(strip.screenID, privacy: .public)")
            store.setOffset(0, for: strip.screenID, notify: false)
            frame = fallbackDockedFrame(size: size, edge: edge, dock: dock)
        }
        if chrome == .collapsed {
            frame = squashToEdge(frame, edge: edge, thickness: 4)
        }
        let changed = !strip.panel.frame.equalTo(frame)
        let chromeChanged = lastChrome[strip.screenID] != chrome
        strip.hosting.clipsToBounds = chrome == .collapsed
        if changed {
            if chromeChanged {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.28
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    strip.panel.animator().setFrame(frame, display: true)
                }
            } else {
                strip.panel.setFrame(frame, display: true)
            }
        }
        lastChrome[strip.screenID] = chrome
        if !strip.panel.isVisible {
            Logger.spaces.info("show \(strip.screenID, privacy: .public) chrome=\(String(describing: chrome), privacy: .public)")
            strip.panel.orderFrontRegardless()
        }
        if chrome == .collapsed, strip.sheet.isVisible {
            strip.sheet.allowsKey = false
            strip.sheet.orderOut(nil)
        }
    }

    private func syncSheet(animated: Bool) {
        guard let id = store.openTabID,
              let screenID = store.openScreenID,
              let strip = strips[screenID],
              strip.panel.isVisible,
              chrome(for: screenID) == .shown else {
            hideSheets(animated: animated)
            presentedTabID = nil
            store.openBump = .zero
            return
        }
        for (otherID, other) in strips where otherID != screenID && other.sheet.isVisible {
            other.sheet.orderOut(nil)
        }
        guard let local = strip.frames[id] else { return }
        guard let screen = screenMatching(id: screenID) else { return }
        let dock = dockingRect(for: screen)
        let tab = store.tabs.first { $0.id == id }
        let explaining = tab?.kind == .smartFilter
        let locked = tab.map { store.isBeyondFreeLimit($0) && $0.kind == .apps } ?? false
        let size: CGSize
        if explaining {
            size = CGSize(width: 340, height: 200)
        } else if locked {
            size = CGSize(width: 300, height: 280)
        } else if store.settings.edge == .bottom, store.settings.respectMenuBarAndDock, let dockBar = DockMetrics.bottomDock(on: screen) {
            size = CGSize(width: dockBar.width, height: sheetHeight(for: tab, dock: dock))
        } else {
            size = CGSize(width: 420, height: sheetHeight(for: tab, dock: dock))
        }
        let tabFrame = screenRect(local, in: strip)
        let edge = store.settings.edge
        let face = sheetFrame(tab: tabFrame, stripFrame: strip.panel.frame, edge: edge, size: size, dock: dock)
        let window = sheetWindowFrame(around: face, edge: edge)
        let hostFrame = face.offsetBy(dx: -window.minX, dy: -window.minY)
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let shouldAnimate = animated && !reduce && (presentedTabID != id || !strip.sheet.isVisible)
        present(strip.sheet, frame: window, host: strip.sheetHost, hostFrame: hostFrame, edge: edge, animated: shouldAnimate)
        store.openBump = bumpInSheet(tabFrame, face: face)
        updateSheetHit(strip)
        presentedTabID = id
    }

    private func present(_ sheet: NSPanel, frame: CGRect, host: NSView, hostFrame: CGRect, edge: ScreenEdge, animated: Bool) {
        let motion = store.settings.sheetMotion
        guard animated else {
            sheet.alphaValue = 1
            sheet.setFrame(frame, display: false)
            host.frame = hostFrame
            if let folder = sheet as? FolderPanel { folder.allowsKey = true }
            if !sheet.isVisible { sheet.orderFrontRegardless() }
            if shouldBecomeKey() { sheet.makeKey() }
            liftStrips()
            DispatchQueue.main.async { self.liftStrips() }
            return
        }
        if motion == .fade {
            sheet.alphaValue = 0
            sheet.setFrame(frame, display: false)
            host.frame = hostFrame
            if let folder = sheet as? FolderPanel { folder.allowsKey = true }
            sheet.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                sheet.animator().alphaValue = 1
            }
            if shouldBecomeKey() { sheet.makeKey() }
            liftStrips()
            DispatchQueue.main.async { self.liftStrips() }
            return
        }
        sheet.alphaValue = 1
        sheet.setFrame(frame, display: false)
        host.frame = hostFrame
        if let folder = sheet as? FolderPanel { folder.allowsKey = true }
        // Add the animation before ordering in, so the first frame is already hidden.
        animateSheetContent(sheet, edge: edge, appearing: true)
        sheet.orderFrontRegardless()
        if shouldBecomeKey() { sheet.makeKey() }
        liftStrips()
        DispatchQueue.main.async { self.liftStrips() }
    }

    private static let slideKey = "skuff.slide"
    private static let slidePhase = "skuff.slidePhase"
    /// How far the folder travels as it slides out from under its tab.
    private static let slideDistance: CGFloat = 36

    /// Slides and fades the folder's content layer; the window itself stays put.
    /// Animating the window frame made the window server move it every frame and
    /// clashed with frame updates during the slide (fitted height, hit path), which
    /// is what made the old slide flicker.
    private func animateSheetContent(
        _ sheet: NSPanel,
        edge: ScreenEdge,
        appearing: Bool,
        completion: (() -> Void)? = nil
    ) {
        guard let layer = sheet.contentView?.layer else {
            completion?()
            return
        }
        // Toward the screen edge, in the superlayer's space (y up).
        let d = Self.slideDistance
        let offset: CGPoint = switch edge {
        case .right: CGPoint(x: d, y: 0)
        case .left: CGPoint(x: -d, y: 0)
        case .top: CGPoint(x: 0, y: d)
        case .bottom: CGPoint(x: 0, y: -d)
        }
        let tucked = CATransform3DMakeTranslation(offset.x, offset.y, 0)
        let move = CABasicAnimation(keyPath: "transform")
        move.fromValue = appearing ? tucked : CATransform3DIdentity
        move.toValue = appearing ? CATransform3DIdentity : tucked
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = appearing ? 0 : 1
        fade.toValue = appearing ? 1 : 0
        let group = CAAnimationGroup()
        group.animations = [move, fade]
        group.duration = appearing ? 0.24 : 0.16
        group.timingFunction = appearing
            ? CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            : CAMediaTimingFunction(name: .easeIn)
        group.setValue(appearing ? "show" : "hide", forKey: Self.slidePhase)
        if !appearing {
            // Stay hidden until the window is ordered out.
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        layer.add(group, forKey: Self.slideKey)
        CATransaction.commit()
    }

    /// Separate look: strip above the sheet. Connected look: sheet (with the tab bump) above inactive tabs.
    private func liftStrips() {
        let connected = store.settings.connectedTab && store.openTabID != nil
        let stripLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + (connected ? 0 : 2))
        let sheetLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + (connected ? 2 : 0))
        for strip in strips.values {
            strip.sheet.hasShadow = !connected
            strip.sheet.level = sheetLevel
            strip.panel.level = stripLevel
            if connected {
                if strip.sheet.isVisible { strip.sheet.orderFrontRegardless() }
            } else if strip.panel.isVisible {
                strip.panel.orderFrontRegardless()
            }
        }
    }

    /// Room around the folder for its shadow, on every side except the screen edge.
    private static let sheetShadowMargin: CGFloat = 16

    private func sheetWindowFrame(around face: CGRect, edge: ScreenEdge) -> CGRect {
        let m = Self.sheetShadowMargin
        switch edge {
        case .right: return CGRect(x: face.minX - m, y: face.minY - m, width: face.width + m, height: face.height + 2 * m)
        case .left: return CGRect(x: face.minX, y: face.minY - m, width: face.width + m, height: face.height + 2 * m)
        case .top: return CGRect(x: face.minX - m, y: face.minY - m, width: face.width + 2 * m, height: face.height + m)
        case .bottom: return CGRect(x: face.minX - m, y: face.minY, width: face.width + 2 * m, height: face.height + m)
        }
    }

    /// The folder's own area on screen, without the shadow margin.
    private func sheetFaceOnScreen(_ strip: StripWindow) -> CGRect {
        strip.sheet.convertToScreen(strip.sheetHost.frame)
    }

    private func bumpInSheet(_ tabScreen: CGRect, face frame: CGRect) -> CGRect {
        return CGRect(
            x: tabScreen.minX - frame.minX,
            y: frame.maxY - tabScreen.maxY,
            width: tabScreen.width,
            height: tabScreen.height
        )
    }

    private func updateSheetHit(_ strip: StripWindow) {
        guard store.settings.connectedTab, store.openTabID != nil else {
            strip.sheetHost.hitPath = nil
            return
        }
        let bounds = strip.sheetHost.bounds
        let path = skuffFolderShape(store: store, tabRect: store.openBump).path(in: bounds)
        strip.sheetHost.hitPath = path.cgPath
    }

    private func hideSheets(animated: Bool) {
        let motion = store.settings.sheetMotion
        for strip in strips.values where strip.sheet.isVisible {
            let edge = store.settings.edge
            let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let sheet = strip.sheet
            guard animated, !reduce else {
                sheet.alphaValue = 1
                sheet.allowsKey = false
                sheet.orderOut(nil)
                continue
            }
            if motion == .fade {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.16
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    sheet.animator().alphaValue = 0
                }, completionHandler: {
                    Task { @MainActor in
                        if self.store.openTabID == nil {
                            sheet.allowsKey = false
                            sheet.orderOut(nil)
                            sheet.alphaValue = 1
                        } else {
                            sheet.alphaValue = 1
                        }
                    }
                })
                continue
            }
            animateSheetContent(sheet, edge: edge, appearing: false) {
                Task { @MainActor in
                    if self.store.openTabID == nil {
                        sheet.allowsKey = false
                        sheet.orderOut(nil)
                    }
                    // Drop the held "hidden" state, unless a reopen already replaced it.
                    if let layer = sheet.contentView?.layer,
                       layer.animation(forKey: Self.slideKey)?.value(forKey: Self.slidePhase) as? String == "hide" {
                        layer.removeAnimation(forKey: Self.slideKey)
                    }
                }
            }
        }
    }

    private func closeIfClickIsOutside(_ point: NSPoint) {
        guard store.openTabID != nil else { return }
        for strip in strips.values {
            if strip.panel.isVisible && strip.panel.frame.contains(point) { return }
            if strip.sheet.isVisible && sheetFaceOnScreen(strip).contains(point) { return }
        }
        store.closeFolder()
    }

    private func screenRect(_ swiftRect: CGRect, in strip: StripWindow) -> CGRect {
        // NSHostingView is flipped, so a SwiftUI frame is already in that view's coordinates.
        let local: CGRect
        if strip.hosting.isFlipped {
            local = swiftRect
        } else {
            let height = strip.hosting.bounds.height
            local = CGRect(x: swiftRect.minX, y: height - swiftRect.maxY, width: swiftRect.width, height: swiftRect.height)
        }
        return strip.panel.convertToScreen(strip.hosting.convert(local, to: nil))
    }

    private static let minSheetHeight: CGFloat = 160

    private func maxSheetHeight(dock: CGRect) -> CGFloat {
        min(520, max(Self.minSheetHeight, dock.height - 32))
    }

    /// App folders fit their grid; folder tabs scroll a file list and keep the full height.
    private func sheetHeight(for tab: FolderTabRecord?, dock: CGRect) -> CGFloat {
        let tallest = maxSheetHeight(dock: dock)
        guard let tab, tab.folderSource == nil else { return tallest }
        let wanted = fittedSheetHeights[tab.id] ?? estimatedSheetHeight(for: tab)
        let height = GeometrySafety.clamp(wanted, min: Self.minSheetHeight, max: tallest)
        shownSheetHeight = (tab.id, height)
        return height
    }

    /// First guess before the grid has been measured; `fitSheet` corrects it.
    private func estimatedSheetHeight(for tab: FolderTabRecord) -> CGFloat {
        let chrome: CGFloat = 32 + 44 + 12 + 28 + 12 + 8
        guard !tab.appBundleIDs.isEmpty else { return chrome + 90 }
        let pinned = tab.pinnedAppBundleIDs.filter { tab.appBundleIDs.contains($0) }.count
        let rest = tab.appBundleIDs.count - pinned
        let pinnedRows = CGFloat((pinned + 2) / 3)
        let rows = CGFloat((rest + 3) / 4)
        var grid = rows * 86 + max(0, rows - 1) * 16
        if pinned > 0 {
            grid += 28 + pinnedRows * 118 + max(0, pinnedRows - 1) * 14 + 16
        }
        return chrome + grid
    }

    /// Spare height shrinks the folder, missing height grows it, up to the usual maximum.
    private func fitSheet(_ id: UUID, slack: CGFloat) {
        guard store.openTabID == id, let shown = shownSheetHeight, shown.id == id else { return }
        let target = (shown.height - slack).rounded()
        guard abs(target - shown.height) > 1 else { return }
        if let previous = fittedSheetHeights[id], abs(previous - target) <= 1 { return }
        fittedSheetHeights[id] = target
        guard !inLayout else { return }
        inLayout = true
        syncSheet(animated: false)
        inLayout = false
    }

    private func sheetFrame(tab: CGRect, stripFrame: CGRect, edge: ScreenEdge, size: CGSize, dock: CGRect) -> CGRect {
        switch edge {
        case .right:
            let cover = stripFrame.width
            let width = min(size.width + cover, max(220, dock.width))
            let fitted = fittedCross(
                anchor: tab.midY,
                span: size.height,
                cover: tab.height,
                limitMin: dock.minY,
                limitMax: dock.maxY
            )
            return CGRect(x: dock.maxX - width, y: fitted.origin, width: width, height: fitted.span)
        case .left:
            let cover = stripFrame.width
            let width = min(size.width + cover, max(220, dock.width))
            let fitted = fittedCross(
                anchor: tab.midY,
                span: size.height,
                cover: tab.height,
                limitMin: dock.minY,
                limitMax: dock.maxY
            )
            return CGRect(x: dock.minX, y: fitted.origin, width: width, height: fitted.span)
        case .top:
            let cover = stripFrame.height
            let height = min(size.height + cover, max(160, dock.height))
            let fitted = fittedCross(
                anchor: tab.midX,
                span: size.width,
                cover: tab.width,
                limitMin: dock.minX,
                limitMax: dock.maxX
            )
            return CGRect(x: fitted.origin, y: dock.maxY - height, width: fitted.span, height: height)
        case .bottom:
            let cover = stripFrame.height
            let height = min(size.height + cover, max(160, dock.height))
            let fitted = fittedCross(
                anchor: tab.midX,
                span: size.width,
                cover: tab.width,
                limitMin: dock.minX,
                limitMax: dock.maxX
            )
            return CGRect(x: fitted.origin, y: dock.minY, width: fitted.span, height: height)
        }
    }

    /// Places `span` so it stays inside the limits and the tab (`cover` around `anchor`) stays on the attached edge.
    private func fittedCross(anchor: CGFloat, span: CGFloat, cover: CGFloat, limitMin: CGFloat, limitMax: CGFloat) -> (origin: CGFloat, span: CGFloat) {
        let room = max(cover + 8, limitMax - limitMin)
        let length = min(max(span, cover + 24), room)
        let margin = min(cover / 2 + 4, max(0, length / 2 - 1))
        var origin = anchor - length / 2
        origin = min(max(origin, limitMin), max(limitMin, limitMax - length))
        let lower = anchor - margin
        let upper = anchor + margin
        if lower < origin {
            origin = min(max(lower, limitMin), max(limitMin, limitMax - length))
        } else if upper > origin + length {
            origin = min(max(upper - length, limitMin), max(limitMin, limitMax - length))
        }
        return (origin, length)
    }

    private func scheduleRelayout(reason: String) {
        Logger.spaces.info("relayout scheduled \(reason, privacy: .public)")
        relayoutWork?.cancel()
        let bumpGeometry = reason == "screen-parameters" || reason == "window-screen"
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if bumpGeometry {
                self.store.screenGeneration += 1
            }
            self.refresh()
        }
        relayoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func noteWindowScreenChange(_ window: NSWindow) {
        let owned = strips.values.contains { $0.panel === window || $0.sheet === window }
        guard owned else { return }
        scheduleRelayout(reason: "window-screen")
    }

    private func updateFullscreenCoverage() {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if front == Bundle.main.bundleIdentifier {
            return
        }
        var next: Set<String> = []
        for screen in NSScreen.screens {
            if FullscreenDetector.coveringApp(on: screen) != nil {
                next.insert(screen.skuffID)
            }
        }
        if next != coveredScreens {
            Logger.spaces.info("fullscreen coverage \(next.sorted().joined(separator: ","), privacy: .public)")
            coveredScreens = next
            hoverExpanded = hoverExpanded.intersection(next)
        }
    }

    private func effectiveBehavior(for screenID: String) -> FullScreenBehavior {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let front, let rule = store.settings.fullScreenExclusions.first(where: { $0.bundleID == front }) {
            return rule.mode == .alwaysShow ? .alwaysShow : .hideCompletely
        }
        guard coveredScreens.contains(screenID) else { return .alwaysShow }
        return store.settings.fullScreenBehavior
    }

    private func chrome(for screenID: String) -> StripChrome {
        if store.tabsManuallyHidden { return .hidden }
        switch effectiveBehavior(for: screenID) {
        case .alwaysShow:
            return .shown
        case .hideCompletely:
            return .hidden
        case .collapseToHandle:
            if hoverExpanded.contains(screenID) || (store.openScreenID == screenID && store.openTabID != nil) {
                return .shown
            }
            return .collapsed
        }
    }

    private func publishCollapsedScreens() {
        let next = Set(strips.keys.filter { chrome(for: $0) == .collapsed })
        if store.collapsedScreens != next {
            store.collapsedScreens = next
        }
    }

    private func handleMouseMoved() {
        let point = NSEvent.mouseLocation
        for strip in strips.values {
            guard effectiveBehavior(for: strip.screenID) == .collapseToHandle else { continue }
            let onEdge = pointerOnDockedEdge(strip, point)
            let onPanel = strip.panel.frame.insetBy(dx: -8, dy: -8).contains(point)
                || (strip.sheet.isVisible && strip.sheet.frame.contains(point))
            if onEdge || onPanel {
                expand(strip.screenID, reason: "pointer")
            } else if hoverExpanded.contains(strip.screenID) {
                scheduleCollapse(strip.screenID)
            }
        }
    }

    private func expand(_ screenID: String, reason: String) {
        collapseTasks[screenID]?.cancel()
        collapseTasks[screenID] = nil
        let inserted = hoverExpanded.insert(screenID).inserted
        if inserted {
            Logger.spaces.info("expand \(screenID, privacy: .public) (\(reason, privacy: .public))")
        }
        if inserted, let strip = strips[screenID] {
            publishCollapsedScreens()
            layout(strip)
        }
    }

    private func scheduleCollapse(_ screenID: String) {
        guard collapseTasks[screenID] == nil else { return }
        collapseTasks[screenID] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self.collapseTasks[screenID] = nil
            guard self.store.openScreenID != screenID || self.store.openTabID == nil else { return }
            let point = NSEvent.mouseLocation
            if let strip = self.strips[screenID] {
                if strip.panel.frame.insetBy(dx: -8, dy: -8).contains(point) { return }
                if self.pointerOnDockedEdge(strip, point) { return }
            }
            self.hoverExpanded.remove(screenID)
            Logger.spaces.info("collapse \(screenID, privacy: .public)")
            self.publishCollapsedScreens()
            if let strip = self.strips[screenID] {
                self.layout(strip)
            }
        }
    }

    private func pointerOnDockedEdge(_ strip: StripWindow, _ point: NSPoint) -> Bool {
        guard let screen = screenMatching(id: strip.screenID) else { return false }
        let dock = dockingRect(for: screen)
        let slop: CGFloat = 6
        switch store.settings.edge {
        case .right:
            return abs(point.x - dock.maxX) <= slop && point.y >= dock.minY && point.y <= dock.maxY
        case .left:
            return abs(point.x - dock.minX) <= slop && point.y >= dock.minY && point.y <= dock.maxY
        case .top:
            return abs(point.y - dock.maxY) <= slop && point.x >= dock.minX && point.x <= dock.maxX
        case .bottom:
            return abs(point.y - dock.minY) <= slop && point.x >= dock.minX && point.x <= dock.maxX
        }
    }

    private func dockingRect(for screen: NSScreen) -> CGRect {
        store.settings.respectMenuBarAndDock ? screen.visibleFrame : screen.frame
    }

    private func squashToEdge(_ frame: CGRect, edge: ScreenEdge, thickness: CGFloat) -> CGRect {
        let thick = max(4, thickness)
        switch edge {
        case .right:
            return CGRect(x: frame.maxX - thick, y: frame.minY, width: thick, height: frame.height)
        case .left:
            return CGRect(x: frame.minX, y: frame.minY, width: thick, height: frame.height)
        case .top:
            return CGRect(x: frame.minX, y: frame.maxY - thick, width: frame.width, height: thick)
        case .bottom:
            return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: thick)
        }
    }

    /// The folder panel is non-activating, so it can take the keyboard without pulling
    /// Skuff forward. It does so whenever the user opened a folder (click or hotkey).
    private func shouldBecomeKey() -> Bool {
        guard NSApp.isActive || store.folderWantsKeyboard else { return false }
        // Only a full-screen app on the folder's own screen keeps the keyboard.
        return !coveredScreens.contains(store.openScreenID ?? "")
    }

    private func screenMatching(id: String) -> NSScreen? {
        NSScreen.screens.first { $0.skuffID == id } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func screenMatchingMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func fallbackDockedFrame(size: CGSize, edge: ScreenEdge, dock: CGRect) -> CGRect {
        switch edge {
        case .right:
            CGRect(x: dock.maxX - size.width, y: dock.midY - size.height / 2, width: size.width, height: size.height)
        case .left:
            CGRect(x: dock.minX, y: dock.midY - size.height / 2, width: size.width, height: size.height)
        case .top:
            CGRect(x: dock.midX - size.width / 2, y: dock.maxY - size.height, width: size.width, height: size.height)
        case .bottom:
            CGRect(x: dock.midX - size.width / 2, y: dock.minY, width: size.width, height: size.height)
        }
    }
}

private enum StripChrome: Equatable {
    case shown
    case collapsed
    case hidden
}

enum FullscreenDetector {
    static func coveringApp(on screen: NSScreen) -> String? {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        let primaryHeight = primary?.frame.height ?? 0
        for window in info {
            if let pid = window[kCGWindowOwnerPID as String] as? Int, pid == Int(ownPID) { continue }
            if let layer = window[kCGWindowLayer as String] as? Int, layer != 0 { continue }
            if let alpha = window[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue < 0.95 { continue }
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary else { continue }
            let width = cgFloat(bounds["Width"])
            let height = cgFloat(bounds["Height"])
            let x = cgFloat(bounds["X"])
            let y = primaryHeight - cgFloat(bounds["Y"]) - height
            let rect = CGRect(x: x, y: y, width: width, height: height)
            guard GeometrySafety.isUsable(rect) else { continue }
            guard rect.width >= screen.frame.width * 0.98, rect.height >= screen.frame.height * 0.98 else { continue }
            let intersection = rect.intersection(screen.frame)
            let screenArea = screen.frame.width * screen.frame.height
            if screenArea > 0, (intersection.width * intersection.height) / screenArea > 0.92 {
                if let pid = window[kCGWindowOwnerPID as String] as? Int {
                    return NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier ?? "pid.\(pid)"
                }
                return "unknown"
            }
        }
        return nil
    }
}

enum DockMetrics {
    /// The Dock bar in AppKit coordinates (origin at the bottom left), when it sits on the bottom edge.
    static func bottomDock(on screen: NSScreen) -> CGRect? {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? screen
        if let topLeft = coreDockFrame() ?? axDockFrame() {
            let rect = CGRect(
                x: topLeft.origin.x,
                y: primary.frame.height - topLeft.origin.y - topLeft.height,
                width: topLeft.width,
                height: topLeft.height
            )
            guard rect.width > 80, rect.width > rect.height, rect.intersects(screen.frame.insetBy(dx: -40, dy: -80)) else { return nil }
            guard rect.midY < screen.frame.minY + screen.frame.height * 0.35 else { return nil }
            return rect
        }
        return estimatedBottomDock(on: screen)
    }

    /// Top-left coordinates of the Dock pill, including minimized windows.
    private static func coreDockFrame() -> CGRect? {
        typealias GetRect = @convention(c) (UnsafeMutablePointer<CGRect>) -> Int32
        guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let symbol = dlsym(handle, "CoreDockGetRect") else { return nil }
        let getRect = unsafeBitCast(symbol, to: GetRect.self)
        var rect = CGRect.zero
        guard getRect(&rect) == 0, rect.width > 80, rect.width > rect.height else { return nil }
        return rect
    }

    private static func axDockFrame() -> CGRect? {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let app = AXUIElementCreateApplication(dockApp.processIdentifier)
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children) == .success,
              let elements = children as? [AXUIElement] else { return nil }
        for element in elements {
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            guard (role as? String) == "AXList" else { continue }
            guard let origin = axPoint(element, kAXPositionAttribute), let size = axSize(element, kAXSizeAttribute) else { continue }
            if size.width > size.height, size.width > 80 {
                return CGRect(origin: origin, size: size)
            }
        }
        return nil
    }

    private static func axPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func axSize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    /// Used when Accessibility cannot see the Dock. Counts the icons stored in the Dock preferences.
    private static func estimatedBottomDock(on screen: NSScreen) -> CGRect? {
        let home = realHome() ?? NSHomeDirectory()
        let url = URL(fileURLWithPath: home).appendingPathComponent("Library/Preferences/com.apple.dock.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        let orientation = plist["orientation"] as? String ?? "bottom"
        guard orientation == "bottom" else { return nil }
        let tile = CGFloat((plist["tilesize"] as? Double) ?? (plist["tilesize"] as? NSNumber)?.doubleValue ?? 48)
        let apps = (plist["persistent-apps"] as? [Any])?.count ?? 0
        let others = (plist["persistent-others"] as? [Any])?.count ?? 0
        let recents = (plist["show-recents"] as? Bool) == true ? ((plist["recent-apps"] as? [Any])?.count ?? 0) : 0
        let icons = apps + others + recents + 1
        guard icons > 1, tile > 8 else { return nil }
        let gap = max(6, tile * 0.14)
        var width = CGFloat(icons) * tile + CGFloat(icons - 1) * gap + tile
        if others > 0 { width += 14 }
        if recents > 0 { width += 14 }
        width = min(width, screen.frame.width - 24)
        let x = screen.frame.midX - width / 2
        return CGRect(x: x, y: screen.frame.minY, width: width, height: tile + 16)
    }

    private static func realHome() -> String? {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return nil }
        return String(cString: dir)
    }
}

private func cgFloat(_ value: Any?) -> CGFloat {
    if let number = value as? NSNumber { return CGFloat(truncating: number) }
    if let number = value as? CGFloat { return number }
    return 0
}

@MainActor
final class StripWindow {
    let screenID: String
    let panel: PassThroughPanel
    let hosting: PassThroughHostingView<EdgeStripView>
    let sheet: FolderPanel
    let sheetHost: ShapedHostingView<FolderSheetContainer>
    var frames: [UUID: CGRect] = [:]
    var controlRect: CGRect = .zero
    var tabStackSize: CGSize = .zero
    var contentSize: CGSize = .zero

    init(
        screenID: String,
        panel: PassThroughPanel,
        hosting: PassThroughHostingView<EdgeStripView>,
        sheet: FolderPanel,
        sheetHost: ShapedHostingView<FolderSheetContainer>
    ) {
        self.screenID = screenID
        self.panel = panel
        self.hosting = hosting
        self.sheet = sheet
        self.sheetHost = sheetHost
    }
}
