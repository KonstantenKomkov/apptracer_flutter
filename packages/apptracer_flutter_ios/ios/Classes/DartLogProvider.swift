import Foundation
import OKTracer

/// Supplies the breadcrumb trail that Tracer attaches to an event.
///
/// The iOS SDK asks its `logProvider` for a `Data` blob when it builds a
/// report, which is the only documented way to attach application logs. Using
/// the provider — rather than the SDK's own file destination — keeps Tracer's
/// internal logging verbosity untouched, so turning breadcrumbs on does not
/// also turn on a flood of SDK diagnostics.
final class DartLogProvider: NSObject, TracerLogProviderProtocol {

    private let lock = NSLock()
    private var lines: [String] = []
    private let maxLines: Int

    init(maxLines: Int) {
        self.maxLines = max(0, maxLines)
    }

    /// Appends one breadcrumb line, evicting the oldest when full.
    func append(_ line: String) {
        guard maxLines > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    /// Drops every buffered line.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        lines.removeAll()
    }

    private func snapshot() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n").data(using: .utf8)
    }

    func getData() -> Data? {
        return snapshot()
    }

    func getData(event: TracerLogEvent) -> Data? {
        return snapshot()
    }
}
