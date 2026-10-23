// Clicks along Skuff's tab strip and reports which points open a folder.
// Needs Accessibility permission for the app running it (e.g. Visual Studio Code).
//
// Usage: swift clicktest.swift [inset] [step]
//   inset: points from the screen edge to click at (default 18, mid-tab)
//   step:  spacing between clicks along the strip (default 8)
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let inset = args.count > 1 ? Double(args[1]) ?? 18 : 18
let step = args.count > 2 ? Double(args[2]) ?? 8 : 8

guard CGPreflightPostEventAccess() else {
    print("No permission to post events. Enable Accessibility for the app running this script, then restart it.")
    exit(2)
}
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "no.voq.skuff").first else {
    print("Skuff is not running.")
    exit(1)
}
let pid = Int(app.processIdentifier)

func windows() -> [CGRect] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { info in
        guard (info[kCGWindowOwnerPID as String] as? Int) == pid,
              let bounds = info[kCGWindowBounds as String] as? [String: Double] else { return nil }
        let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
        return rect.width > 1 && rect.height > 1 ? rect : nil
    }
}

// The strip is Skuff's smallest visible window; the folder panel is wider than 150 pt.
guard let strip = windows().min(by: { $0.width * $0.height < $1.width * $1.height }) else {
    print("No visible tab strip.")
    exit(1)
}
func folderOpen() -> Bool {
    windows().contains { $0 != strip && $0.width > 150 }
}

// Window coordinates are top-left based, like CGEvent positions.
let screens = NSScreen.screens.map { screen -> CGRect in
    let main = NSScreen.screens[0].frame
    let f = screen.frame
    return CGRect(x: f.minX, y: main.maxY - f.maxY, width: f.width, height: f.height)
}
let screen = screens.first { $0.intersects(strip) } ?? screens[0]
let vertical = strip.height > strip.width
var points: [CGPoint] = []
// Skip the last 50 pt: the grip and + button sit at the end of the strip.
if vertical {
    let x = abs(strip.maxX - screen.maxX) < 2 ? strip.maxX - inset : strip.minX + inset
    for y in stride(from: strip.minY + 12, through: strip.maxY - 50, by: step) { points.append(CGPoint(x: x, y: y)) }
} else {
    let y = abs(strip.maxY - screen.maxY) < 2 ? strip.maxY - inset : strip.minY + inset
    for x in stride(from: strip.minX + 12, through: strip.maxX - 50, by: step) { points.append(CGPoint(x: x, y: y)) }
}

func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func escape() {
    CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
}

print("Strip \(strip) on screen \(screen), \(points.count) clicks")
let original = CGEvent(source: nil)?.location ?? .zero
if folderOpen() { escape(); usleep(500_000) }
var map = ""
var misses: [Int] = []
for p in points {
    post(.mouseMoved, p)
    usleep(180_000)
    post(.leftMouseDown, p)
    usleep(70_000)
    post(.leftMouseUp, p)
    usleep(500_000)
    if folderOpen() {
        map += "#"
        escape()
        usleep(450_000)
        if folderOpen() {
            post(.leftMouseDown, p); usleep(70_000); post(.leftMouseUp, p); usleep(450_000)
        }
    } else {
        map += "."
        misses.append(Int(vertical ? p.y : p.x))
    }
}
post(.mouseMoved, original)
print("map: \(map)")
print("hits \(points.count - misses.count), misses \(misses.count)\(misses.isEmpty ? "" : " at \(vertical ? "y" : "x") = \(misses)")")
