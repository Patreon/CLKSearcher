Pod::Spec.new do |s|
  s.name             = "CLKSearcher"
  s.version          = "1.0.2"
  s.summary          = "CLKSearcher is the best way to allow your users to keyword search over remote and local content"
  s.homepage         = "https://github.com/Patreon/CLKSearcher"
  s.license          = 'Apache 2.0'
  s.author           = { "21echoes" => "david@patreon.com" }
  s.source           = { :git => "git://github.com/Patreon/CLKSearcher.git", :tag => s.version.to_s }

  s.dependency 'FrameAccessor', '~> 1.3.2'

  s.platform     = :ios, '7.0'
  s.requires_arc = true
  s.source_files = 'Pod/Classes'
end
