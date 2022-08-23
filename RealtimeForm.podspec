#
# Be sure to run `pod lib lint Realtime.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'RealtimeForm'
  s.version          = '0.9.7'
  s.summary          = 'Reactive input form.'
  s.description      = <<-DESC
  Reactive input form based on Combine for UIKit.
                       DESC

  s.homepage         = 'https://github.com/k-o-d-e-n/Realtime'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'k-o-d-e-n' => 'koden.u8800@gmail.com' }
  s.source           = { :git => 'https://github.com/k-o-d-e-n/Realtime.git', :tag => '0.9.7' }
  s.social_media_url = 'https://twitter.com/K_o_D_e_N'
  s.ios.deployment_target = '9.0'
  s.osx.deployment_target = '10.10'
  s.swift_version = '5.0'
  s.default_subspec = 'Core'
  s.subspec 'Core' do |core|
    core.source_files = [
        'Sources/Realtime/Classes/Realtime/Support/Form.swift',
        'Sources/Realtime/Classes/Realtime/Support/Row.swift',
        'Sources/Realtime/Classes/Realtime/Support/Section.swift',
        'Sources/Realtime/Classes/Realtime/Support/ReusableItem.swift',
        'Sources/Realtime/Classes/Realtime/Support/UITableView.swift',
        'Sources/Realtime/Classes/Realtime/Support/ReuseController.swift',
        'Sources/Realtime/Classes/Realtime/Support/DynamicSection.swift'
    ]
  end
  s.subspec 'Combine' do |combine|
    combine.dependency 'RealtimeForm/Core'
    combine.pod_target_xcconfig = { 'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => ['$(inherited)', 'COMBINE'] }
    combine.ios.deployment_target = '13.0'
  end
  s.subspec 'Listenable' do |listenable|
    listenable.dependency 'RealtimeForm/Core'
    listenable.dependency 'Realtime/Listenable'
    listenable.pod_target_xcconfig = { 'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => ['$(inherited)', 'REALTIME_UI'] }
  end
end
