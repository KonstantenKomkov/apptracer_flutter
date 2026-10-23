import FlutterMacOS
import Foundation
import Sentry

public final class ApptracerDesktopPlugin: NSObject, FlutterPlugin {
    private static let lifecycle = DesktopLifecycle()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "apptracer_flutter_desktop/lifecycle",
                                           binaryMessenger: registrar.messenger)
        registrar.addMethodCallDelegate(ApptracerDesktopPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard ["initNativeSdk", "closeNativeSdk", "clearNativeSdk"].contains(call.method) else {
            result(FlutterMethodNotImplemented); return
        }
        let arguments = call.arguments as? [String: Any] ?? [:]
        guard Self.lifecycle.authorize(arguments["owner"] as? String) else {
            result(["state": "error", "reason": "native_sentry_already_owned"]); return
        }
        switch call.method {
        case "initNativeSdk":
            result(Self.lifecycle.start(arguments))
        case "closeNativeSdk": Self.lifecycle.stop(completion: result)
        case "clearNativeSdk": Self.lifecycle.clear(completion: result)
        default: result(FlutterMethodNotImplemented)
        }
    }
}

/// Kept process-wide: neither another Dart adapter nor a second Flutter engine
/// can reopen the crash writer after stop without a process restart.
private final class DesktopLifecycle: NSObject {
    private var attempted = false
    private var owner: String?
    private var hasSession = false
    private var stopping = false
    private var waiters: [FlutterResult] = []
    private var state: [String: String] = ["state": "disabled"]
    private let gate = NSLock()
    private var accepting = false

    private var storage: DesktopStorage {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        var cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil {
            cache.appendPathComponent(Bundle.main.bundleIdentifier ?? "")
        }
        return DesktopStorage(library: library, bundleID: Bundle.main.bundleIdentifier ?? "",
                              diagnosticCache: cache)
    }

    func authorize(_ candidate: String?) -> Bool {
        guard let candidate = candidate, !candidate.isEmpty else { return false }
        if owner == nil { owner = candidate }
        return owner == candidate
    }

    private func permit(_ allowed: Bool) {
        gate.lock(); accepting = allowed; gate.unlock()
    }
    private func maySend() -> Bool {
        gate.lock(); defer { gate.unlock() }; return accepting
    }
    private func fail(_ reason: String) -> [String: String] {
        state = ["state": "error", "reason": reason]; return state
    }

    func start(_ arguments: [String: Any]) -> [String: String] {
        if state["state"] == "error" { return state }
        if attempted { return state["state"] == "enabled" ? state :
            ["state": "restartRequired", "reason": "macos_restart_required"] }
        guard !SentrySDK.isEnabled else { return fail("native_sentry_already_owned") }
        guard let dsn = arguments["dsn"] as? String,
              let url = URL(string: dsn), url.host != nil, url.user?.isEmpty == false,
              url.password == nil, !url.path.isEmpty,
              url.scheme == "https" || (url.scheme == "http" &&
                ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "")) else {
            return fail("invalid_native_dsn")
        }
        do { try storage.prepare(preserve: arguments["preservePreviousReports"] as? Bool ?? false) }
        catch { return fail("native_storage_prepare_failed") }
        attempted = true
        RevocableSession.shared.open()
        hasSession = true
        permit(true)
        SentrySDK.start { options in
            options.dsn = dsn
            options.releaseName = arguments["release"] as? String
            if let environment = arguments["environment"] as? String {
                options.environment = environment
            }
            options.dist = arguments["dist"] as? String
            options.maxBreadcrumbs = (arguments["maxBreadcrumbs"] as? NSNumber)?.uintValue ?? 100
            options.maxCacheItems = (arguments["maxCacheItems"] as? NSNumber)?.uintValue ?? 30
            options.cacheDirectoryPath = self.storage.queue.path
            options.urlSession = RevocableSession.shared.sdkSession
            options.shutdownTimeInterval = 0
            options.debug = false
            options.sendDefaultPii = false
            options.sendClientReports = false
            options.enableAutoSessionTracking = false
            options.enableAutoBreadcrumbTracking = false
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false
            options.enableSwizzling = false
            options.enableAutoPerformanceTracing = false
            options.enableTimeToFullDisplayTracing = false
            options.enableWatchdogTerminationTracking = false
            options.enableAppHangTracking = false
            options.experimental.enableLogs = false
            options.enableSpotlight = false
            options.tracesSampleRate = 0
            options.profilesSampleRate = 0
            options.beforeSend = { [weak self] event in self?.maySend() == true ? event : nil }
        }
        guard SentrySDK.isEnabled else { permit(false); return fail("native_start_failed") }
        state = ["state": "enabled"]
        return state
    }

    func stop(completion: @escaping FlutterResult) {
        permit(false)
        if stopping { waiters.append(completion); return }
        guard attempted || !SentrySDK.isEnabled else {
            completion(fail("native_sentry_already_owned")); return
        }
        // Persist before shutdown, so a process death cannot authorize replay.
        do { try storage.markRevoked() }
        catch { _ = fail("native_revoke_failed") }
        guard hasSession else {
            if state["state"] != "error" {
                state = attempted ? ["state": "restartRequired", "reason": "macos_stopped_restart_required"]
                                  : ["state": "disabled"]
            }
            completion(state); return
        }
        stopping = true
        state = state["state"] == "error" ? state :
            ["state": "restartRequired", "reason": "macos_shutdown_pending"]
        waiters.append(completion)
        // In-flight bytes cannot be recalled, but no new requests may start after
        // session invalidation. Invalidation completes before stop is acknowledged.
        RevocableSession.shared.revoke { [weak self] error in
            guard let self = self else { return }
            self.hasSession = false
            if error != nil { _ = self.fail("native_session_shutdown_failed") }
            self.finishStop()
        }
        SentrySDK.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self, self.stopping else { return }
            _ = self.fail("native_session_shutdown_timeout")
            self.finishStop()
        }
    }

    private func finishStop() {
        guard stopping else { return }
        stopping = false
        if state["state"] != "error" {
            state = ["state": "restartRequired", "reason": "macos_stopped_restart_required"]
        }
        let callbacks = waiters; waiters.removeAll()
        for callback in callbacks { callback(state) }
    }

    func clear(completion: @escaping FlutterResult) {
        stop { [weak self] _ in
            guard let self = self else { return }
            guard self.state["state"] != "error" else { completion(self.state); return }
            do {
                try self.storage.clear()
                self.state = self.attempted ?
                    ["state": "restartRequired", "reason": "macos_cleared_restart_required"] :
                    ["state": "disabled"]
                completion(self.state)
            } catch { completion(self.fail("native_cleanup_failed")) }
        }
    }
}
