import Foundation

let files = FileManager.default
let temporary = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try files.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? files.removeItem(at: temporary) }
let cache = temporary.appendingPathComponent("Caches")
try files.createDirectory(at: cache, withIntermediateDirectories: true)
try Data("diagnostics".utf8).write(to: cache.appendingPathComponent("async.log"))
try Data("other-app-data".utf8).write(to: cache.appendingPathComponent("unrelated"))
let storage = DesktopStorage(library: temporary, bundleID: "dev.apptracer.storage-test", diagnosticCache: cache)
let payload = storage.queue.appendingPathComponent("nested/report")
func seed() throws {
    try files.createDirectory(at: payload.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("account-A-secret".utf8).write(to: payload)
}
func mustFail(_ action: () throws -> Void) {
    do { try action(); fatalError("Unsafe storage operation succeeded") } catch { }
}

try storage.prepare(preserve: false)
try seed()
try storage.prepare(preserve: true)
let preserved = try String(contentsOf: payload, encoding: .utf8)
assert(preserved == "account-A-secret")
try storage.prepare(preserve: false)
assert(!files.fileExists(atPath: payload.path))
try seed()
try storage.markRevoked()
try storage.prepare(preserve: true)
assert(!files.fileExists(atPath: payload.path), "Revocation must override preservation")
try seed()
try storage.clear()
assert(!files.fileExists(atPath: cache.appendingPathComponent("async.log").path))
assert(files.fileExists(atPath: cache.appendingPathComponent("unrelated").path))
let attrs = try files.attributesOfItem(atPath: storage.queue.path)
assert(attrs[.type] as? FileAttributeType == .typeRegular)
assert((attrs[.size] as? NSNumber)?.intValue == 0)
mustFail { try seed() } // An old SDK writer cannot recreate directories.
try storage.clear() // Idempotent before and after initialization.
try storage.prepare(preserve: true)
assert(!files.fileExists(atPath: payload.path))

let outside = temporary.appendingPathComponent("unrelated")
try files.createDirectory(at: outside, withIntermediateDirectories: true)
let sentinel = outside.appendingPathComponent("keep")
try Data("do-not-delete".utf8).write(to: sentinel)
try files.removeItem(at: storage.queue)
try files.createSymbolicLink(at: storage.queue, withDestinationURL: outside)
mustFail { try storage.clear() }
mustFail { try storage.prepare(preserve: false) }
assert(files.fileExists(atPath: sentinel.path))
try files.removeItem(at: storage.queue)
try files.removeItem(at: storage.root)
try files.createSymbolicLink(at: storage.root, withDestinationURL: outside)
mustFail { try storage.clear() }
assert(files.fileExists(atPath: sentinel.path))
mustFail { try DesktopStorage(library: temporary, bundleID: "../escape").clear() }

// Late official-SDK work must get a normal cancellation, never Foundation's
// exception for a task created on an invalidated URLSession.
let session = RevocableSession.shared
session.open()
var revoked = false
session.revoke { error in assert(error == nil); revoked = true }
let deadline = Date().addingTimeInterval(5)
while !revoked && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
assert(revoked)
let completed = DispatchSemaphore(value: 0)
session.sdkSession!.dataTask(with: URL(string: "http://127.0.0.1:1/")!) { data, response, error in
    assert(response == nil && error != nil)
    completed.signal()
}.resume()
assert(completed.wait(timeout: .now() + 5) == .success)
print("Native storage and revoked-session checks passed")
