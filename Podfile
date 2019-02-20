platform :ios, '10.3'

target 'Zotero' do
  use_frameworks!

  pod 'Alamofire', '4.8.0'
  pod 'KeychainSwift', '13.0.0'
  pod 'RealmSwift', '3.13.1'
  pod 'RxAlamofire', '4.3.0'
  pod 'RxSwift', '4.4.0'
  pod 'RxCocoa', '4.4.0'
  pod 'CocoaLumberjack/Core', '3.4.2'
  pod 'CocoaLumberjack/Swift', '3.4.2'
  pod 'DictionaryDecoder', '0.9.2'
  pod 'PSPDFKit', podspec: 'https://customers.pspdfkit.com/cocoapods/TRIAL-w46OJ57xowLmzqz6rPM9wXSiSGlj4MoudWW3bLnjX57qJwfJzSvdP91d8wsAAPH9fMwzL_6osqqa2mS6VwkcXw/latest.podspec'

  target 'ZoteroTests' do
    inherit! :search_paths
    
    pod 'Quick', '1.3.2'
    pod 'Nimble', '7.3.1'
  end

  target 'ZoteroUITests' do
    inherit! :search_paths
    # Pods for testing
  end

end
