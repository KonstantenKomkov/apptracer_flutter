Pod::Spec.new do |s|
  s.name             = 'apptracer_flutter_ios'
  s.version          = '0.1.2'
  s.summary          = 'iOS implementation of apptracer_flutter.'
  s.description      = <<-DESC
Unofficial Flutter integration with Tracer (apptracer.ru). Forwards Dart errors,
breadcrumbs and custom keys to the OKTracer iOS SDK.

This pod is not published by VK or OK.TECH and does not redistribute their SDK:
it declares OKTracer as a dependency, which CocoaPods resolves from the vendor's
own spec repository. Add this line to your Podfile:

    source 'https://github.com/odnoklassniki/tracer-ios.git'
    source 'https://cdn.cocoapods.org/'
                       DESC
  s.homepage         = 'https://github.com/KonstantenKomkov/apptracer_flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Константин Комков' => 'fireandmight@gmail.com' }
  s.source           = { :path => '.' }
  # The Swift Package Manager layout, shared with Package.swift so that a
  # CocoaPods application and a Swift Package Manager one build the same
  # files.
  s.source_files     = 'apptracer_flutter_ios/Sources/apptracer_flutter_ios/**/*'
  s.dependency 'Flutter'
  # 1.5.2 is the first version served from nexus-external.vkteam.ru. Every
  # earlier spec downloads from artifactory-external.vkpartner.ru, which the
  # vendor shut down on 2026-08-31, so any of them fails at `pod install` with
  # a 404. For an application with 1.5.1 in its Podfile.lock the floor turns
  # that 404 into a resolver message naming the constraint; `pod update
  # OKTracer` is what moves it on.
  s.dependency 'OKTracer', '>= 1.5.2'

  # Matches the deployment target of the OKTracer xcframework (iOS 12.4).
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'

  # Adds the dSYM-upload build phase to the application's target, the way
  # firebase_crashlytics does: a phase declared here would belong to this pod
  # and run before the application is even linked, when Runner.app.dSYM does
  # not exist yet.
  #
  # The work is in `tracer_add_upload_phase`, a standalone script, because on
  # Swift Package Manager nothing evaluates this podspec and the step has to be
  # runnable by hand. See the package README.
  #
  # Set TRACER_SKIP_IOS_PHASE=1 to keep pod install away from the project file.
  if ENV['TRACER_SKIP_IOS_PHASE'].to_s.empty?
    begin
      require_relative 'tracer_add_upload_phase'
      # The directory holding the Podfile, i.e. the application's `ios/`.
      # Dir.pwd during podspec evaluation is this plugin's own directory.
      project_dir = Pod::Config.instance.installation_root.to_s
      add_phase(File.join(project_dir, 'Runner.xcodeproj'), 'Runner')
    rescue StandardError => error
      Pod::UI.warn "apptracer_flutter: could not add the dSYM upload phase " \
                   "(#{error.class}); see the package README for the manual step."
    end
  end
end
