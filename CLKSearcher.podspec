Pod::Spec.new do |s|
  s.name             = "CLKSearcher"
  s.version          = "0.1.0"
  s.summary          = "CLKSearcher is the best way to allow your users to keyword search over remote and local content"
  s.homepage         = "https://github.com/Clinkle/CLKSearcher"
  s.license          = 'MIT'
  s.author           = { "tsheaff" => "tyler@clinkle.com" }
  s.source           = { :git => "git://github.com/Clinkle/CLKSearcher.git", :tag => s.version.to_s }

  s.dependency 'FrameAccessor', '~> 1.3.2'

  s.platform     = :ios, '7.0'
  s.requires_arc = true
  s.source_files = 'Pod/Classes'
end
