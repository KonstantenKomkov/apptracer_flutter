#import "GeneratedPluginRegistrant.h"
#import <Flutter/Flutter.h>

// Use the engine's scene and registration lifecycle when it provides one.
// Flutter 3.22 instead exposes the implicit engine through its view controller.
#if __has_include(<Flutter/FlutterSceneDelegate.h>)
@protocol ExamplePluginRegistrant <FlutterPluginRegistrant>
@end
#else
@protocol ExamplePluginRegistrant <NSObject>
- (void)registerWithRegistry:(NSObject<FlutterPluginRegistry> * _Nonnull)registry;
@end
#endif

NS_INLINE Class _Nonnull exampleSceneDelegateClass(
    FlutterAppDelegate<ExamplePluginRegistrant> * _Nonnull delegate, Class _Nonnull legacyClass) {
#if __has_include(<Flutter/FlutterSceneDelegate.h>)
  delegate.pluginRegistrant = delegate;
  return FlutterSceneDelegate.class;
#else
  return legacyClass;
#endif
}
