import Foundation

@main struct StorageTest {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let storage = CollectionStorage(library: root, bundleID: "test.app")
        let queue = root.appendingPathComponent("TracerStorage")
        let crash = root.appendingPathComponent("Caches/ru.ok.tracer.crashreporter.data/test.app")
        let unrelated = root.appendingPathComponent("unrelated")
        try Data("keep".utf8).write(to: unrelated)
        try storage.prepare(purge: false)
        try Data("pending".utf8).write(to: queue.appendingPathComponent("pending"))
        try Data("crash".utf8).write(to: crash.appendingPathComponent("live_report.okcrash"))
        try storage.revoke()
        precondition(storage.isRevoked)
        for target in [queue, crash] {
            var directory: ObjCBool = false
            precondition(fm.fileExists(atPath: target.path, isDirectory: &directory) && !directory.boolValue)
            do {
                try Data("after revoke".utf8).write(to: target.appendingPathComponent("new-report"))
                fatalError("revoked writer was allowed")
            } catch { }
        }
        let untouched = try Data(contentsOf: unrelated)
        precondition(untouched == Data("keep".utf8))
        // A fresh instance sees revocation; re-consent discards old reports.
        let next = CollectionStorage(library: root, bundleID: "test.app")
        precondition(next.isRevoked)
        try next.prepare(purge: true)
        precondition(!next.isRevoked)
        let remaining = try fm.contentsOfDirectory(atPath: queue.path)
        precondition(remaining.isEmpty)
        try storage.revoke()
        try fm.removeItem(at: queue)
        try fm.createSymbolicLink(at: queue, withDestinationURL: root)
        do { try next.prepare(purge: true); fatalError("symlink accepted") }
        catch { }
        precondition(next.isRevoked)
        precondition(fm.fileExists(atPath: unrelated.path))
        print("Storage checks passed: purge, durable revoke, blocked writes, re-consent, symlink failure, unrelated files.")
    }
}
