#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint revnix_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'revnix_flutter'
  s.version          = '1.5.0'
  s.summary          = 'Revnix subscriptions and entitlements for Flutter.'
  s.description      = <<-DESC
Flutter plugin for Revnix: in-app subscriptions, entitlements, placements
and purchase registration, bridging the native revnix-swift SDK (StoreKit 2).
                       DESC
  s.homepage         = 'https://revnix.io'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Revnix' => 'support@revnix.io' }
  s.source           = { :path => '.' }
  # revnix-swift is the git submodule at ios/revnix_flutter/Revnix, compiled
  # straight into this module.
  s.source_files = 'revnix_flutter/Sources/revnix_flutter/**/*.swift',
                   'revnix_flutter/Revnix/Sources/Revnix/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '16.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = { 'revnix_flutter_privacy' => ['revnix_flutter/Revnix/Sources/Revnix/PrivacyInfo.xcprivacy'] }
end
