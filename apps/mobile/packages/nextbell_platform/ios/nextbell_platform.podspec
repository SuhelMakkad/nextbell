# Local fallback for CocoaPods projects; the app uses Swift Package Manager.
Pod::Spec.new do |s|
  s.name = 'nextbell_platform'
  s.version = '1.0.0'
  s.summary = 'Native multi-account authorization and persistent alarms for Nextbell.'
  s.description = 'Private app plugin using GoogleSignIn and iOS 26 AlarmKit. Not published to a package registry.'
  s.homepage = 'https://example.invalid/nextbell'
  s.license = { :file => '../LICENSE' }
  s.author = 'Nextbell maintainer'
  s.source = { :path => '.' }
  s.source_files = 'nextbell_platform/Sources/nextbell_platform/**/*'
  s.dependency 'Flutter'
  s.dependency 'GoogleSignIn', '= 10.0.0'
  s.platform = :ios, '26.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
  s.resource_bundles = {'nextbell_platform_privacy' => ['nextbell_platform/Sources/nextbell_platform/PrivacyInfo.xcprivacy']}
end
