#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint revnix_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'revnix_flutter'
  s.version          = '0.2.0'
  s.summary          = 'Revnix subscriptions and entitlements for Flutter.'
  s.description      = <<-DESC
Flutter plugin for Revnix — in-app subscriptions, entitlements, placements
and purchase registration, bridging the native revnix-swift SDK (StoreKit 2).
                       DESC
  s.homepage         = 'https://revnix.io'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Revnix' => 'support@revnix.io' }
  s.source           = { :path => '.' }
  # revnix-swift 0.2.0 is VENDORED under Sources/revnix_flutter/Revnix (glob
  # below picks it up) until it ships to CocoaPods — then remove that folder
  # and restore:  s.dependency 'Revnix', '~> 0.2'
  s.source_files = 'revnix_flutter/Sources/revnix_flutter/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '16.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'revnix_flutter_privacy' => ['revnix_flutter/Sources/revnix_flutter/PrivacyInfo.xcprivacy']}
end
