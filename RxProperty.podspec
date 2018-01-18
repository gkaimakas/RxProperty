Pod::Spec.new do |s|
    s.name             = 'RxProperty'
    s.version          = '0.1.0'
    s.summary          = 'ReactiveSwift Property, MutableProperty & ValidatingProperty'

    s.description      = <<-DESC
            A shameless attempt to recreate ReactiveSwift's Property, MutableProperty & ValidatingProperty
            in RxSwift.
                       DESC

    s.homepage         = 'https://github.com/gkaimakas/RxProperty'
    s.license          = { :type => 'MIT', :file => 'LICENSE' }
    s.author           = { 'gkaimakas' => 'gkaimakas@gmail.com' }
    s.source           = { :git => 'https://github.com/gkaimakas/RxProperty.git', :tag => s.version.to_s }

    s.ios.deployment_target = '11.0'

    s.source_files = 'RxProperty/Classes/**/*'
    s.dependency 'RxSwift'
end
