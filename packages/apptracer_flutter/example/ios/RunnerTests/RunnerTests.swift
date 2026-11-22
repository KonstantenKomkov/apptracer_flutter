import Flutter
import UIKit
import XCTest

final class RunnerTests: XCTestCase {
  @MainActor
  func testSceneDisplaysFlutterAndRegistersPlugins() {
    let ready = NSPredicate { _, _ in
      let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
      guard let controller = windows.compactMap({ $0.rootViewController as? FlutterViewController }).first else {
        return false
      }
      return controller.isDisplayingFlutterUI
        && controller.hasPlugin("AppTracerFlutterPlugin")
        && controller.hasPlugin("ru.apptracer.flutter.example/native")
    }
    let frame = XCTNSPredicateExpectation(predicate: ready, object: nil)
    wait(for: [frame], timeout: 45)
  }
}
