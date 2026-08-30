# The body of the "[apptracer_flutter] Upload dSYMs to Tracer" build phase.
#
# Added to Runner.xcodeproj automatically at `pod install`; on Swift Package
# Manager nothing evaluates the podspec, so this file is what you paste into a
# Run Script phase by hand. See the package README.
#
# Safe to delete: without it, upload dSYMs yourself with
#   dart run apptracer_flutter:upload_symbols ios --token=…
[ "$CONFIGURATION" = "Release" ] || exit 0

TOKEN="${TRACER_IOS_PLUGIN_TOKEN:-${TRACER_PLUGIN_TOKEN:-}}"
if [ -z "$TOKEN" ] && [ -f "$SRCROOT/tracer_plugin_token" ]; then
  TOKEN="$(cat "$SRCROOT/tracer_plugin_token")"
fi
if [ -z "$TOKEN" ]; then
  echo "warning: apptracer_flutter: no iOS pluginToken, skipping dSYM upload."
  echo "warning: set TRACER_IOS_PLUGIN_TOKEN, or put the token in ios/tracer_plugin_token."
  exit 0
fi

# The phase runs in `ios/`; the package and pubspec.yaml live one level up.
cd "$SRCROOT/.." || exit 0

"$FLUTTER_ROOT/bin/dart" run apptracer_flutter:upload_symbols ios \
  --dir="$DWARF_DSYM_FOLDER_PATH" --token="$TOKEN" ||
  echo "warning: apptracer_flutter: dSYM upload failed; crashes of this build will be unreadable."
