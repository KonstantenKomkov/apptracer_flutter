#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds the dSYM-upload build phase to an application's Xcode target.
#
#   ruby tracer_add_upload_phase.rb -p <app>/ios -n Runner.xcodeproj [-t Runner]
#
# The podspec runs this at `pod install`, the way firebase_crashlytics runs its
# own crashlytics_add_upload_symbols. It is a standalone script rather than a
# method the podspec requires, because on Swift Package Manager no podspec is
# evaluated and the step has to be runnable by hand — see the package README.
#
# A script phase declared in the podspec itself would not work: it would belong
# to the pod target and run before the application is linked, so
# `DWARF_DSYM_FOLDER_PATH` would point at this plugin's framework and
# `Runner.app.dSYM` would not exist yet. Only a phase on the application's own
# target runs late enough.
#
# The phase never fails a build. A symbol upload that blocks an archive because
# of a network hiccup is worse than one that warns; the fail-closed path is
# `dart run apptracer_flutter:upload_symbols`, meant for CI.

require 'optparse'

PHASE_NAME = '[apptracer_flutter] Upload dSYMs to Tracer'
PHASE_SCRIPT = File.read(File.join(__dir__, 'tracer_dsym_upload_phase.sh')).freeze

# Warns through CocoaPods when it is there, and through stderr when this script
# is run by hand.
def warn_out(message)
  if defined?(Pod::UI)
    Pod::UI.warn("apptracer_flutter: #{message}")
  else
    warn("apptracer_flutter: #{message}")
  end
end

def say(message)
  if defined?(Pod::UI)
    Pod::UI.puts("apptracer_flutter: #{message}")
  else
    puts("apptracer_flutter: #{message}")
  end
end

def add_phase(project_path, target_name)
  begin
    require 'xcodeproj'
  rescue LoadError
    warn_out('the xcodeproj gem is not installed, so the dSYM upload phase ' \
             'was not added. Install it with `gem install xcodeproj`, or add ' \
             'the phase in Xcode yourself — see the package README.')
    return false
  end

  unless File.exist?(project_path)
    warn_out("#{project_path} not found; add the dSYM upload step yourself, " \
             'see the package README.')
    return false
  end

  project = Xcodeproj::Project.open(project_path)
  target = project.targets.find { |t| t.name == target_name }
  if target.nil?
    warn_out("no target named #{target_name}; add the dSYM upload step " \
             'yourself, see the package README.')
    return false
  end

  existing = target.shell_script_build_phases.find { |p| p.name == PHASE_NAME }
  if existing
    # Idempotent, and it keeps an edited script up to date across upgrades.
    return true if existing.shell_script == PHASE_SCRIPT

    existing.shell_script = PHASE_SCRIPT
    project.save
    say('refreshed the dSYM upload build phase.')
    return true
  end

  phase = target.new_shell_script_build_phase(PHASE_NAME)
  phase.shell_script = PHASE_SCRIPT
  phase.show_env_vars_in_log = '0'
  project.save
  say("added the dSYM upload build phase to #{target_name}. Delete it in " \
      'Xcode if you upload symbols another way.')
  true
end

# Only when run directly: the podspec loads this file for `add_phase`.
if $PROGRAM_NAME == __FILE__
  options = { project_name: 'Runner.xcodeproj', target_name: 'Runner' }
  OptionParser.new do |parser|
    parser.banner = 'Adds the Tracer dSYM upload phase to an Xcode target. ' \
                    "Usage: tracer_add_upload_phase.rb [options]"
    parser.on('-p', '--projectDirectory=DIR', String,
              "Directory holding the Xcode project, i.e. the application's ios/") do |dir|
      options[:project_dir] = dir
    end
    parser.on('-n', '--projectName=NAME', String,
              'Name of the Xcode project (default: Runner.xcodeproj)') do |name|
      options[:project_name] = name
    end
    parser.on('-t', '--targetName=NAME', String,
              'Name of the target to add the phase to (default: Runner)') do |name|
      options[:target_name] = name
    end
  end.parse!

  abort('apptracer_flutter: pass -p, the directory holding Runner.xcodeproj.') unless options[:project_dir]

  ok = add_phase(
    File.join(options[:project_dir], options[:project_name]),
    options[:target_name]
  )
  exit(ok ? 0 : 1)
end
