Pod::Spec.new do |s|
  s.name             = 'apptracer_flutter_ios'
  s.version          = '0.1.0'
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
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'OKTracer', '>= 1.4.0'

  # Matches the deployment target of the OKTracer xcframework (iOS 12.4).
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'
end
