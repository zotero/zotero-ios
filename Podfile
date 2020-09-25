platform :ios, '13.0'

target 'Zotero' do
    use_frameworks!

    pod 'Alamofire', '5.2.2'
    pod 'CocoaLumberjack/Core', '3.6.2'
    pod 'CocoaLumberjack/Swift', '3.6.2'
    pod 'KeychainSwift', '19.0.0'
    pod 'RealmSwift', '5.4.3'
    pod 'RxAlamofire', '5.6.1'
    pod 'RxSwift', '5.1.1'
    pod 'RxSwiftExt', '5.2.0'
    pod 'SwiftGen', '6.3.0'
    pod 'SwiftyGif', '5.3.0'
    pod 'ZIPFoundation', '0.9.11'

    #pspdfkit

    target 'ZShare' do
      inherit! :search_paths
    end

    target 'ZoteroTests' do
      inherit! :search_paths

    	pod 'Quick', '3.0.0'
    	pod 'Nimble', '8.1.2'
    	pod 'OHHTTPStubs', '9.0.0'
    end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings.delete 'IPHONEOS_DEPLOYMENT_TARGET'
    end
  end
end
