import Flutter
import Foundation
import OKTracer

/// iOS half of `apptracer_flutter`.
///
/// Forwards Dart errors, breadcrumbs and custom keys to the OKTracer SDK.
/// Native crashes, hangs and MetricKit reports are handled by that SDK
/// directly and are none of this plugin's business.
public class AppTracerFlutterPlugin: NSObject, FlutterPlugin {

    private static let channelName = "ru.apptracer.flutter/tracer"

    /// Property keys the iOS SDK overwrites while processing a report.
    /// Documented by Tracer; writing to them silently loses data.
    private static let reservedPropertyKeys: Set<String> = ["message", "file", "issueKey"]

    private var service: TracerServiceProtocol?
    private var serviceDelegate: DebugServiceDelegate?
    private var logProvider: DartLogProvider?
    private var enabled = false
    private var debug = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = AppTracerFlutterPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        case "initialize":
            result(initialize(arguments))
        case "stopCollection":
            stopCollection()
            result(nil)
        case "recordError":
            recordError(arguments)
            result(nil)
        case "recordLog":
            if let message = arguments["message"] as? String {
                logProvider?.append(message)
            }
            result(nil)
        case "setCustomKey":
            if let key = arguments["key"] as? String, let value = arguments["value"] as? String {
                setCustomKey(key: key, value: value)
            }
            result(nil)
        case "removeCustomKey":
            // The iOS SDK has no remove operation; an empty value is the
            // closest available equivalent and keeps the key visible as
            // deliberately cleared rather than stale.
            if let key = arguments["key"] as? String {
                setCustomKey(key: key, value: "")
            }
            result(nil)
        case "setUserId":
            if let userId = arguments["userId"] as? String {
                service?.setUserId(userId)
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func initialize(_ arguments: [String: Any]) -> Bool {
        debug = arguments["debug"] as? Bool ?? false

        guard let appToken = arguments["appToken"] as? String, !appToken.isEmpty else {
            NSLog("[apptracer_flutter] TracerOptions.appToken is required on iOS; collection is off.")
            enabled = false
            return false
        }

        let maxBreadcrumbs = arguments["maxBreadcrumbs"] as? Int ?? 100
        let provider = DartLogProvider(maxLines: maxBreadcrumbs)
        logProvider = provider

        let endpoint = EndpointConfiguration(token: appToken, url: arguments["apiUrl"] as? String)
        // Под `debug` SDK получает вывод в консоль, а его результаты —
        // делегата. Без них об отправленном нефатальном событии не известно
        // ничего: send(nonFatal:) ничего не возвращает, и «событие не дошло»
        // невозможно отличить от «событие не отправлялось».
        let destinations: [TracerLogDestination] =
            debug ? [.console(minLevel: .debug), .file()] : [.file()]
        let configuration = Configuration(
            endpoint,
            features: [
                .crashReporter(config: TracerCrashReporterConfiguration()),
                .assertReporter(config: TracerAssertReporterConfiguration())
            ],
            sysInfoProvider: nil,
            logProvider: provider,
            logDestinations: destinations
        )

        let delegate = debug ? DebugServiceDelegate() : nil
        serviceDelegate = delegate
        let created = TracerFactory.tracerService(
            configuration: configuration,
            delegate: delegate
        )
        created.start()
        service = created

        if let environment = arguments["environment"] as? String {
            created.setEnvironment(environment)
        }
        if let initial = arguments["initialCustomKeys"] as? [String: String] {
            let sanitized = initial.filter { !Self.reservedPropertyKeys.contains($0.key) }
            if !sanitized.isEmpty {
                created.update(properties: sanitized)
            }
        }

        enabled = true
        logDebug("started, token \(appToken.prefix(6))…")
        return true
    }

    /// Diagnostics behind `TracerOptions.debug`.
    ///
    /// The iOS SDK reports nothing about a submitted non-fatal — not even
    /// whether it went out — so without this there is no way to tell a report
    /// that never left the device from one the backend dropped.
    private func logDebug(_ message: String) {
        guard debug else { return }
        NSLog("[apptracer_flutter] \(message)")
    }

    private func stopCollection() {
        enabled = false
        service?.stop()
        logProvider?.clear()
    }

    private func setCustomKey(key: String, value: String) {
        guard enabled, !Self.reservedPropertyKeys.contains(key) else { return }
        service?.update(properties: [key: value])
    }

    private func recordError(_ arguments: [String: Any]) {
        guard enabled, let service = service else { return }

        let exceptionType = arguments["exceptionType"] as? String ?? "DartError"
        let message = arguments["message"] as? String ?? ""
        let title = message.isEmpty ? exceptionType : "\(exceptionType): \(message)"

        let stack = arguments["stackTrace"] as? [String: Any]
        let frames = stack?["frames"] as? [[String: Any]] ?? []
        let symbols = Self.callStackSymbols(from: frames)

        var properties: [String: String] = [:]
        if let custom = arguments["customKeys"] as? [String: String] {
            for (key, value) in custom where !Self.reservedPropertyKeys.contains(key) {
                properties[key] = value
            }
        }
        properties["dart.exception_type"] = exceptionType
        if stack?["obfuscated"] as? Bool == true {
            properties["dart.obfuscated"] = "true"
            if let buildId = stack?["buildId"] as? String {
                properties["dart.build_id"] = buildId
            }
        }

        // Grouping needs an explicit key on iOS.
        //
        // A Dart stack trace has no native call-stack addresses, and Tracer
        // ignores a supplied symbol array unless a debugger is attached, so a
        // release build has nothing left to group on and would collapse every
        // Dart error in the app into one issue. A key derived from the Dart
        // error type and its top frame restores per-error grouping.
        let issueKey = (arguments["issueKey"] as? String)
            ?? Self.syntheticIssueKey(exceptionType: exceptionType, frames: frames)

        let model = TracerNonFatalModel(
            message: title,
            // Адреса обязаны быть непустыми. Измерено 26.08.2026 на живом
            // проекте: с пустым массивом SDK отбрасывает событие ещё до сети,
            // отвечая делегату `callStackAddresses is empty` из
            // CrashReporterService.getThreadInfo, и в проект не приходит
            // ничего. У стектрейса Dart нативных адресов нет, поэтому берётся
            // нативный стек самого вызова: он одинаков для всех ошибок Dart и
            // потому бесполезен для группировки — её держит issueKey, который
            // синтезируется на стороне Dart.
            traceType: .custom(
                callStackAddresses: Self.placeholderCallStack,
                threadName: "dart:isolate",
                callStackSymbols: symbols,
                dropFirstSymbols: 0
            ),
            tags: [:],
            properties: properties,
            issueKey: issueKey,
            severity: Self.severity(from: arguments["severity"] as? String)
        )
        service.send(nonFatal: model)
        logDebug("sent non-fatal \(exceptionType), issueKey \(issueKey)")
    }

    private static func callStackSymbols(from frames: [[String: Any]]) -> [String] {
        return frames.compactMap { frame in
            if let raw = frame["raw"] as? String {
                return raw.trimmingCharacters(in: .whitespaces)
            }
            return nil
        }
    }

    /// Stands in for the native call stack a Dart error does not have.
    ///
    /// The array may not be empty: with `[]` the SDK drops the report before
    /// any network call, answering `callStackAddresses is empty` — measured
    /// 2026-08-26. Passing the real `Thread.callStackReturnAddresses` satisfies
    /// that, but fills the report with twenty frames of UIKit, CoreFoundation
    /// and libdispatch that have nothing to do with the error, each rendered as
    /// `Missing Binary image` in the console. A single placeholder satisfies the
    /// same requirement and costs one unreadable line; the Dart stack trace
    /// travels in the attached log either way, which is the copy that is
    /// actually readable.
    private static let placeholderCallStack: [NSNumber] = [0]

    /// Maximum length of an `issueKey`.
    ///
    /// `LIMIT_MAX_ISSUE_KEY_LENGTH = 32` is declared in the Android SDK's
    /// BuildConfig. Whether it truncates or rejects could not be established
    /// from the bytecode, and the iOS SDK does not publish an equivalent — but
    /// a synthetic key of `dart/<Type>/<member>` runs to 37–56 characters in
    /// ordinary cases, so if truncation does happen it happens on nearly every
    /// event. Two different errors sharing a 32-character prefix would then
    /// merge into one group, which is worse than not grouping at all.
    ///
    /// Staying inside 32 characters costs nothing and removes the question.
    private static let maxIssueKeyLength = 32

    /// Builds a grouping key from the Dart error type and the innermost named
    /// frame, bounded to `maxIssueKeyLength` characters.
    ///
    /// **Neither the file nor the line number is included, deliberately.**
    /// Tracer computes `crashId` from a title and subtitle and explicitly
    /// ignores file names and line numbers, so that editing a file does not
    /// scatter one issue across several groups. An `issueKey`, by contrast, is
    /// used verbatim: putting a line number in it would reintroduce exactly the
    /// instability Tracer went out of its way to avoid.
    private static func syntheticIssueKey(exceptionType: String, frames: [[String: Any]]) -> String {
        for frame in frames {
            if let member = frame["member"] as? String {
                return issueKey(identity: "dart/\(exceptionType)/\(member)", readable: member)
            }
            // An obfuscated AOT build has no names at all, only addresses, and
            // those move with every build. Grouping is per-build here, because
            // nothing stable is left to key on. See docs/symbolication.md.
            if let virt = frame["virtAddress"] as? String {
                return issueKey(identity: "dart/\(exceptionType)/virt+\(virt)", readable: "virt+\(virt)")
            }
        }
        return issueKey(identity: "dart/\(exceptionType)", readable: exceptionType)
    }

    /// Produces a key of at most `maxIssueKeyLength` characters.
    ///
    /// When it fits, `identity` is used as-is and stays fully readable. When it
    /// does not, the key becomes the tail of `readable` plus a digest of the
    /// *whole* `identity`, so two errors whose readable parts trimmed to the
    /// same text still land in different groups.
    ///
    /// The tail of the member is kept rather than the head: the method name
    /// says more than the class prefix it hangs off, and the Dart error type is
    /// already in the event title, so repeating it inside the key would spend
    /// scarce characters on nothing.
    private static func issueKey(identity: String, readable: String) -> String {
        if identity.count <= maxIssueKeyLength {
            return identity
        }
        let digest = String(String(format: "%08x", fnv1a(identity)).prefix(6))
        let budget = maxIssueKeyLength - digest.count - 3  // "d/" and "#"
        let tail = String(readable.suffix(budget))
        return "d/\(tail)#\(digest)"
    }

    /// FNV-1a, 32-bit. Four lines long, and stable across runs and platforms —
    /// Swift's `hashValue` is seeded per process and would hand out a different
    /// grouping key on every launch.
    private static func fnv1a(_ text: String) -> UInt32 {
        var hash: UInt32 = 2166136261
        for byte in Array(text.utf8) {
            hash = (hash ^ UInt32(byte)) &* 16777619
        }
        return hash
    }

    private static func severity(from name: String?) -> ReportSeverity {
        switch name {
        case "fatal": return .fatal
        case "warning": return .warning
        case "notice": return .notice
        case "info": return .info
        case "debug": return .debug
        default: return .error
        }
    }
}

/// Логирует то, что SDK сообщает о себе, когда включён `TracerOptions.debug`.
///
/// Держится плагином за сильную ссылку: делегат в `TracerFactory` слабый, и без
/// этого он умер бы сразу после `initialize`.
private final class DebugServiceDelegate: TracerServiceDelegate {

    func tracerDidRegister(result: TracerResult<FeatureType>) { log("register", result) }
    func tracerDidStart(result: TracerResult<FeatureType>) { log("start", result) }
    func tracerDidStop(result: TracerResult<FeatureType>) { log("stop", result) }
    func tracerDidEvent(feature: FeatureType, result: TracerResult<String>) {
        log("event \(feature.rawValue)", result)
    }
    func tracerDidUpload(feature: FeatureType, result: TracerResult<String>) {
        log("upload \(feature.rawValue)", result)
    }
    func tracerDidRegisterObject(result: TracerResult<FeatureObject>) {}
    func tracerDidStartObject(result: TracerResult<FeatureObject>) {}
    func tracerDidStopObject(result: TracerResult<FeatureObject>) {}
    func tracerDidRemoveObject(result: TracerResult<FeatureObject>) {}
    func tracerDidAllUpload(feature: FeatureType) {
        NSLog("[apptracer_flutter] OKTracer upload queue drained: \(feature.rawValue)")
    }

    private func log<T>(_ what: String, _ result: TracerResult<T>) {
        switch result {
        case .success(let value):
            NSLog("[apptracer_flutter] OKTracer \(what): ok \(value)")
        case .failure(let error):
            let ns = error as NSError
            NSLog(
                "[apptracer_flutter] OKTracer \(what): FAILED "
                    + "\(type(of: error)) domain=\(ns.domain) code=\(ns.code) "
                    + "\(ns.localizedDescription) userInfo=\(ns.userInfo)"
            )
        }
    }
}
