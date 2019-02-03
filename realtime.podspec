#
# Be sure to run `pod lib lint Realtime.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'Realtime'
  s.version          = '0.9'
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
  s.source           = { :git => 'https://github.com/k-o-d-e-n/Realtime.git', :tag => '0.8.5' }
  s.social_media_url = 'https://twitter.com/K_o_D_e_N'
  s.ios.deployment_target = '9.0'
  s.swift_version = '4.1'
  s.source_files = 'Realtime/Classes/**/*'
  s.static_framework = true
  s.dependency 'Firebase/Core'
  s.dependency 'Firebase/Database'
  s.dependency 'Firebase/Storage'
  s.xcconfig = {
      "FRAMEWORK_SEARCH_PATHS" => "'$(PODS_ROOT)'"
  }
end
