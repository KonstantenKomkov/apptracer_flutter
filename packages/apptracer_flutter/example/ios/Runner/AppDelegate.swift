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
