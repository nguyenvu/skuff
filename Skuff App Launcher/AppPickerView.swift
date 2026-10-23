import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppPickerView: View {
    @ObservedObject var store: LibraryStore
    @Binding var selected: [String]
    var onDone: () -> Void
    @State private var query = ""
    @State private var draft: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Apps").font(.headline)
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
            List {
                ForEach(filtered, id: \.bundleID) { app in
                    Toggle(isOn: Binding(
                        get: { draft.contains(app.bundleID) },
                        set: { on in
                            if on { draft.insert(app.bundleID) } else { draft.remove(app.bundleID) }
                        }
                    )) {
                        HStack(spacing: 8) {
                            Image(nsImage: store.icon(for: app.bundleID))
                                .resizable()
                                .frame(width: 22, height: 22)
                            Text(app.name).lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .frame(minHeight: 280)
            HStack {
                Button("Browse…") { browse() }
                Spacer()
                Button("Cancel", action: onDone)
                Button("Add") {
                    var next = selected
                    for id in draft where !next.contains(id) {
                        next.append(id)
                    }
                    selected = next
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420, height: 480)
        .onAppear { draft = Set(selected) }
    }

    private var filtered: [InstalledApp] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let apps = store.apps.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !needle.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedStandardContains(needle) || $0.bundleID.localizedStandardContains(needle)
        }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = AppInspector.bundleID(of: url) else { continue }
            let name = AppInspector.displayName(of: url)
            if store.apps[id] == nil {
                store.apps[id] = InstalledApp(
                    bundleID: id,
                    name: name,
                    url: url,
                    category: AppInspector.category(of: url)
                )
            }
            draft.insert(id)
        }
    }
}

@MainActor
final class AppPickerPresenter {
    static let shared = AppPickerPresenter()
    private var window: NSPanel?
    private var box: AppPickerBox?

    func present(store: LibraryStore, selected: [String], onChange: @escaping ([String]) -> Void) {
        let box = AppPickerBox(ids: selected)
        self.box = box
        let binding = Binding(
            get: { box.ids },
            set: { box.ids = $0 }
        )
        let root = AppPickerView(store: store, selected: binding, onDone: { [weak self] in
            onChange(box.ids)
            self?.close()
        })
        let host = NSHostingController(rootView: root)
        let panel = NSPanel(contentViewController: host)
        panel.styleMask = [.titled, .closable]
        panel.title = "Add Apps"
        panel.setContentSize(NSSize(width: 420, height: 480))
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 4)
        panel.isReleasedWhenClosed = false
        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
    }
}

private final class AppPickerBox {
    var ids: [String]
    init(ids: [String]) { self.ids = ids }
}
