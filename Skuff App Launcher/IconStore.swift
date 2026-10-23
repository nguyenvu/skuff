import AppKit
import Foundation
import QuickLookThumbnailing
import UniformTypeIdentifiers

enum IconStoreError: LocalizedError {
    case unreadable
    case tooLarge
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unreadable: "Skuff couldn't read that image."
        case .tooLarge: "Choose an image smaller than 8 MB."
        case .unsupported: "Choose a PNG, JPEG, HEIC, PDF, or SVG image."
        }
    }
}

enum IconStore {
    static var directory: URL {
        folder("Skuff/Icons")
    }

    static var thumbnailDirectory: URL {
        folder("Skuff/FolderThumbs")
    }

    private static func folder(_ name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func image(named filename: String) -> NSImage? {
        let file = directory.appendingPathComponent(filename)
        if filename.lowercased().hasSuffix(".svg") {
            let preview = file.deletingPathExtension().appendingPathExtension("preview.png")
            if let image = NSImage(contentsOf: preview), image.isValid {
                return image
            }
        }
        guard let image = NSImage(contentsOf: file), image.isValid else { return nil }
        return image
    }

    static func importImage(from url: URL) async throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        let allowed: Set<String> = ["png", "jpg", "jpeg", "heic", "pdf", "svg"]
        guard allowed.contains(ext) else { throw IconStoreError.unsupported }
        let data = try Data(contentsOf: url)
        guard data.count <= 8_000_000 else { throw IconStoreError.tooLarge }
        if ext == "svg" {
            let filename = UUID().uuidString + ".svg"
            let destination = directory.appendingPathComponent(filename)
            try data.write(to: destination, options: .atomic)
            try await writePreview(for: destination)
            return filename
        }
        guard let image = rasterImage(from: url, data: data) else { throw IconStoreError.unreadable }
        let scaled = downscaled(image, maxSide: 128)
        let filename = UUID().uuidString + ".png"
        let destination = directory.appendingPathComponent(filename)
        guard let tiff = scaled.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw IconStoreError.unreadable
        }
        try png.write(to: destination, options: .atomic)
        return filename
    }

    static func delete(_ filename: String?) {
        guard let filename, !filename.isEmpty else { return }
        let file = directory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: file)
        if filename.lowercased().hasSuffix(".svg") {
            let preview = file.deletingPathExtension().appendingPathExtension("preview.png")
            try? FileManager.default.removeItem(at: preview)
        }
    }

    /// Stages every image first, so a failed write keeps the current icons.
    static func replaceAll(with encoded: [String: String]) throws {
        let fileManager = FileManager.default
        let folder = directory
        let staging = folder.deletingLastPathComponent()
            .appendingPathComponent("Icons-import-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        for (filename, base64) in encoded {
            guard let data = Data(base64Encoded: base64) else { continue }
            let safeName = URL(fileURLWithPath: filename).lastPathComponent
            guard !safeName.isEmpty, safeName == filename else { continue }
            try data.write(to: staging.appendingPathComponent(safeName), options: .atomic)
        }
        if let existing = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for file in existing {
                try? fileManager.removeItem(at: file)
            }
        }
        let staged = try fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
        for file in staged {
            try fileManager.moveItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
        }
    }

    static func clearThumbnailCache() {
        FolderThumbnails.shared.removeAll()
        let folder = thumbnailDirectory
        if let existing = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for file in existing {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private static func rasterImage(from url: URL, data: Data) -> NSImage? {
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = NSPDFImageRep(data: data) else { return nil }
            let image = NSImage(size: pdf.size)
            image.addRepresentation(pdf)
            return image
        }
        let image = NSImage(data: data)
        return image?.isValid == true ? image : nil
    }

    private static func downscaled(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let size = image.size
        let longest = max(size.width, size.height, 1)
        let scale = longest > maxSide ? maxSide / longest : 1
        let newSize = NSSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
        let output = NSImage(size: newSize)
        output.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize), from: .zero, operation: .copy, fraction: 1)
        output.unlockFocus()
        return output
    }

    private static func writePreview(for destination: URL) async throws {
        let request = QLThumbnailGenerator.Request(
            fileAt: destination,
            size: CGSize(width: 128, height: 128),
            scale: 2,
            representationTypes: .all
        )
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
           let tiff = representation.nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            let preview = destination.deletingPathExtension().appendingPathExtension("preview.png")
            try png.write(to: preview, options: .atomic)
            return
        }
        if NSImage(contentsOf: destination)?.isValid == true {
            return
        }
        try? FileManager.default.removeItem(at: destination)
        throw IconStoreError.unreadable
    }
}
