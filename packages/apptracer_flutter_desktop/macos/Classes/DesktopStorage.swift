import Foundation

/// Only this adapter's namespace is touched. A file at `queue` prevents late SDK
/// writers from recreating a purged directory until the next authorized process.
struct DesktopStorage {
    let library: URL
    let bundleID: String
    // Cocoa 8.58.4 puts its async diagnostic log outside cacheDirectoryPath.
    // Only that exact file is removed; other applications' caches are untouched.
    var diagnosticCache: URL? = nil
    private let files = FileManager.default

    var root: URL {
        library.appendingPathComponent("Application Support/apptracer_desktop")
            .appendingPathComponent(bundleID).appendingPathComponent("v1")
    }
    var queue: URL { root.appendingPathComponent("queue") }
    private var revoked: URL { root.appendingPathComponent("revoked") }

    private func attributes(_ url: URL) throws -> [FileAttributeKey: Any]? {
        do { return try files.attributesOfItem(atPath: url.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    private func validate(_ url: URL) throws {
        guard !bundleID.isEmpty, bundleID != ".", bundleID != "..",
              !bundleID.contains("/") else { throw Failure.unsafePath }
        var current = url
        while current.path != library.path {
            guard current.path.hasPrefix(library.path + "/") else { throw Failure.unsafePath }
            if try attributes(current)?[.type] as? FileAttributeType == .typeSymbolicLink {
                throw Failure.unsafePath
            }
            current.deleteLastPathComponent()
        }
    }

    private func remove(_ url: URL) throws {
        try validate(url)
        if try attributes(url) != nil { try files.removeItem(at: url) }
    }

    func markRevoked() throws {
        try validate(revoked)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("revoked\n".utf8).write(to: revoked, options: .atomic)
    }

    func clear() throws {
        try markRevoked()
        try remove(queue)
        try Data().write(to: queue, options: .atomic)
        if let diagnosticCache = diagnosticCache {
            try remove(diagnosticCache.appendingPathComponent("async.log"))
        }
    }

    func prepare(preserve: Bool) throws {
        try validate(queue)
        try validate(revoked)
        let wasRevoked = try attributes(revoked) != nil
        if !preserve || wasRevoked {
            try remove(queue)
        }
        try files.createDirectory(at: queue, withIntermediateDirectories: true)
        try remove(revoked)
    }

    enum Failure: Error { case unsafePath }
}
