import Foundation

/// Storage layout audited against OKTracer 1.5.2 only (dependency pinned).
/// Empty files replace the SDK directories after revocation. This prevents its
/// surviving crash writer from reopening a report after service.stop(). Open
/// file descriptors may finish writing to unlinked files, never queued paths.
struct CollectionStorage {
    let library: URL
    let bundleID: String
    private let files = FileManager.default

    private var marker: URL {
        library.appendingPathComponent("Application Support/apptracer_flutter/collection-revoked")
    }

    var isRevoked: Bool {
        do {
            _ = try files.attributesOfItem(atPath: marker.path)
            return true
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return false
        } catch {
            // An unreadable consent marker must never authorize startup.
            return true
        }
    }

    private var targets: [URL] {
        [library.appendingPathComponent("TracerStorage"),
         library.appendingPathComponent("Caches/ru.ok.tracer.crashreporter.data")
            .appendingPathComponent(bundleID)]
    }

    /// Never follow a symlink out of the app's SDK storage.
    private func validate(_ url: URL) throws {
        guard !bundleID.isEmpty, bundleID != ".", bundleID != "..",
              !bundleID.contains("/") else { throw StorageError.unsafePath }
        var current = url
        while current.path != library.path {
            guard current.path.hasPrefix(library.path + "/") else {
                throw StorageError.unsafePath
            }
            if let attributes = try? files.attributesOfItem(atPath: current.path),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw StorageError.unsafePath
            }
            current.deleteLastPathComponent()
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        try validate(url)
        do { try files.removeItem(at: url) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { }
    }

    func markRevoked() throws {
        try validate(marker)
        try files.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("revoked\n".utf8).write(to: marker, options: .atomic)
    }

    func revoke() throws {
        try markRevoked()
        // Do not return success unless both paths have been replaced.
        for target in targets {
            try removeIfPresent(target)
            try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: target, options: .atomic)
        }
    }

    /// Called before constructing any SDK object, after explicit permission.
    func prepare(purge: Bool) throws {
        for target in targets {
            try validate(target)
            if purge { try removeIfPresent(target) }
            try files.createDirectory(at: target, withIntermediateDirectories: true)
        }
        // A failed cleanup leaves the marker intact and prevents auto-start.
        try removeIfPresent(marker)
    }

    enum StorageError: Error { case unsafePath }
}
