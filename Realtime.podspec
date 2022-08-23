#
# Be sure to run `pod lib lint Realtime.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'Realtime'
  s.version          = '0.9.7'
  s.summary          = 'Firebase Realtime Database framework.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
  Realtime is database framework based on Firebase that makes the creation of complex database structures is simple. :exclamation:
  Realtime can help you to create app quicker than if use clear Firebase API herewith to apply complex structures to store data in Firebase database, to update UI using reactive behaviors.
  Realtime provides lightweight data traffic, lazy initialization of data, good distribution of data
                       DESC

  s.homepage         = 'https://github.com/k-o-d-e-n/Realtime'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'k-o-d-e-n' => 'koden.u8800@gmail.com' }
  s.source           = { :git => 'https://github.com/k-o-d-e-n/Realtime.git', :tag => '0.9.7' }
  s.social_media_url = 'https://twitter.com/K_o_D_e_N'
  s.ios.deployment_target = '10.0'
  s.osx.deployment_target = '10.10'
  s.swift_version = '5.0'
  s.exclude_files = 'Sources/Realtime/support.databaseValue.realtime.swift.gyb'
  s.static_framework = true
  s.default_subspec = 'Core'
  s.subspec 'Core' do |core|
      core.source_files = 'Sources/Realtime/Classes/Realtime/*.swift', 'Sources/Realtime/Classes/*.swift'
      core.dependency 'Realtime/Listenable'
  end
  s.subspec 'Listenable' do |listenable|
      listenable.source_files = 'Sources/Realtime/Classes/Listenable/**/*', 'Sources/Realtime/Classes/realtime.swift'
      listenable.dependency 'Promise.swift', '~> 0.6.1'
  end
  s.subspec 'UI' do |ui|
      ui.source_files = 'Sources/Realtime/Classes/Realtime/Support/**/*'
      ui.pod_target_xcconfig = { 'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => ['$(inherited)', 'REALTIME_UI'] }
  end
  s.subspec 'Firebase' do |firebase|
      firebase.source_files = 'Sources/Realtime+Firebase/**/*'
      firebase.dependency 'Realtime/Core'
      firebase.dependency 'Firebase/Database'
      firebase.dependency 'Firebase/Storage'
  end
  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/RealtimeTestLib/**.*'
  end
  s.xcconfig = {
      "FRAMEWORK_SEARCH_PATHS" => "'$(PODS_ROOT)'"
  }
end
