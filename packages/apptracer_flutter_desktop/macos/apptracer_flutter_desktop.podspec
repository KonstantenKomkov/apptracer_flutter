Pod::Spec.new do |s|
  s.name = 'apptracer_flutter_desktop'
  s.version = '0.1.0'
  s.summary = 'Managed macOS lifecycle for the official Sentry SDK.'
  s.description = s.summary
  s.homepage = 'https://github.com/KonstantenKomkov/apptracer_flutter'
  s.license = { :type => 'MIT' }
  s.author = 'apptracer_flutter'
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.dependency 'Sentry/HybridSDK', '8.58.4'
  s.osx.deployment_target = '12.0'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
