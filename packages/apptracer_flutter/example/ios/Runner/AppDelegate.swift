import Flutter
import OKTracer
import UIKit

/// Hosts the channel that triggers a native crash.
///
/// A Dart error never reaches the native crash reporter, so check 12 of the
/// live-verification plan needs a genuine native crash to confirm the pairing
/// works. `TracerFactory.raise(crash:)` is the vendor's own trigger, which
/// makes the crash arrive exactly as their SDK expects rather than through
/// some signal we raised ourselves.
///
/// There is no ANR counterpart here: on iOS the equivalent is the SDK's hang
/// counter, which is not something an application triggers on demand.
@main
@objc class AppDelegate: FlutterAppDelegate {

  private static let channelName = "ru.apptracer.flutter.example/native"
  private var verificationEngine: FlutterEngine?
  private var verificationChannel: FlutterMethodChannel?

  private func checkSecondaryEngine(result: @escaping FlutterResult) {
    guard verificationEngine == nil else {
      result(FlutterError(code: "probe_busy", message: nil, details: nil))
      return
    }
    let engine = FlutterEngine(name: "consent-verification", project: nil, allowHeadlessExecution: true)
    verificationEngine = engine
    guard engine.run(withEntrypoint: "secondaryConsentProbe") else {
      verificationEngine = nil
      result(FlutterError(code: "probe_start_failed", message: nil, details: nil))
      return
    }
    GeneratedPluginRegistrant.register(with: engine)
    let channel = FlutterMethodChannel(
      name: "ru.apptracer.flutter.example/secondary", binaryMessenger: engine.binaryMessenger)
    verificationChannel = channel
    channel.setMethodCallHandler { [weak self] call, reply in
      guard call.method == "result" else { reply(FlutterMethodNotImplemented); return }
      reply(nil)
      result(call.arguments)
      DispatchQueue.main.async {
        channel.setMethodCallHandler(nil)
        engine.destroyContext()
        self?.verificationChannel = nil
        self?.verificationEngine = nil
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: Self.channelName,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "checkSecondaryEngine":
          self.checkSecondaryEngine(result: result)
        case "verificationContext":
          // Used only by the standalone acceptance entrypoint. No credentials
          // or other process environment values are exposed.
          result([
            "scenario": ProcessInfo.processInfo.environment["APPTRACER_VERIFY_SCENARIO"] ?? "inspect",
            "libraryPath": FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].path
          ])
        case "crashForConsentVerification":
          result(nil)
          fatalError("apptracer consent verification native crash")
        case "crashNatively":
          // Answer first: after this the process is gone, and an unanswered
          // call would leave the Dart side waiting on a reply that can never
          // arrive.
          result(nil)
          TracerFactory.raise(crash: .fatal)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
