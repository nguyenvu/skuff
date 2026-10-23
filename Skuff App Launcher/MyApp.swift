import AppKit
import SwiftUI

@main
struct SkuffApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            SettingsView(store: delegate.store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = LibraryStore()
    private var panels: PanelController?
    private var settings: SettingsPresenter?
    private var statusItem: NSStatusItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsPresenter(store: store)
        self.settings = settings
        store.presentSettings = { [weak settings] in
            settings?.show()
        }
        store.onChange = { [weak self] in
            self?.panels?.refresh()
        }
        store.presentTogglePanel = { [weak self] in
            self?.panels?.togglePanel()
        }
        let panels = PanelController(store: store)
        self.panels = panels
        panels.start()
        store.bootstrap()
        installStatusItem()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Skuff")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        let toggle = NSMenuItem(title: "Hide Tabs", action: #selector(toggleTabs), keyEquivalent: "")
        toggle.target = self
        let restore = NSMenuItem(title: "Restore Default Tabs…", action: #selector(restoreDefaultTabs), keyEquivalent: "")
        restore.target = self
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(toggle)
        menu.addItem(restore)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Skuff", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleTabs() {
        panels?.togglePanel()
    }

    @objc private func restoreDefaultTabs() {
        store.confirmRestoreDefaultTabs()
    }

    @objc private func showSettings() {
        store.showSettings()
    }

    @objc private func bringTabsBack() {
        panels?.bringTabsBack()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Bring tabs back", action: #selector(bringTabsBack), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let hidden = store.tabsManuallyHidden || !(panels?.tabsAreVisible() ?? true)
        menu.item(at: 0)?.title = hidden ? "Show Tabs" : "Hide Tabs"
    }
}

@MainActor
final class SettingsPresenter: NSObject, NSWindowDelegate {
    private let store: LibraryStore
    private var window: NSWindow?

    init(store: LibraryStore) {
        self.store = store
    }

    func show() {
        DispatchQueue.main.async { [weak self] in
            self?.present()
        }
    }

    private func present() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let window = window ?? makeWindow()
        self.window = window
        window.level = .floating
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: SettingsView(store: store))
        let window = NSWindow(contentViewController: host)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 640))
        window.minSize = NSSize(width: 520, height: 460)
        window.maxSize = NSSize(width: 720, height: 700)
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
