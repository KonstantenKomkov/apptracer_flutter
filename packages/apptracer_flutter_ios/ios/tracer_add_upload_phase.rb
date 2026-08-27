# Adds the dSYM-upload build phase to the application's Xcode target.
#
# Run from the podspec at `pod install`, the way firebase_crashlytics does it.
# A script phase declared in this podspec would not work: it belongs to the pod
# target and runs before the application is linked, so `DWARF_DSYM_FOLDER_PATH`
# points at this plugin's framework and `Runner.app.dSYM` does not exist yet.
# Only a phase on the application's own target runs late enough.
#
# The phase itself never fails a build. A symbol upload that blocks an archive
# because of a network hiccup is worse than one that warns; the fail-closed
# path is `dart run apptracer_flutter:upload_symbols`, meant for CI.
require 'xcodeproj'

PHASE_NAME = '[apptracer_flutter] Upload dSYMs to Tracer'.freeze

PHASE_SCRIPT = <<~'SH'
  # Added by apptracer_flutter at pod install. Safe to delete: without it,
  # upload dSYMs yourself with
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
SH

def add_phase(project_path, target_name)
  unless File.exist?(project_path)
    Pod::UI.warn "apptracer_flutter: #{project_path} not found; add the dSYM " \
                 'upload step yourself, see the package README.'
    return
  end

  project = Xcodeproj::Project.open(project_path)
  target = project.targets.find { |t| t.name == target_name }
  if target.nil?
    Pod::UI.warn "apptracer_flutter: no target named #{target_name}; add the " \
                 'dSYM upload step yourself, see the package README.'
    return
  end

  existing = target.shell_script_build_phases.find { |p| p.name == PHASE_NAME }
  if existing
    # Idempotent, and it keeps an edited script up to date across upgrades.
    return if existing.shell_script == PHASE_SCRIPT

    existing.shell_script = PHASE_SCRIPT
    project.save
    Pod::UI.puts "apptracer_flutter: refreshed the dSYM upload build phase."
    return
  end

  phase = target.new_shell_script_build_phase(PHASE_NAME)
  phase.shell_script = PHASE_SCRIPT
  phase.show_env_vars_in_log = '0'
  project.save
  Pod::UI.puts "apptracer_flutter: added the dSYM upload build phase to " \
               "#{target_name}. Delete it in Xcode if you upload symbols " \
               'another way.'
end
