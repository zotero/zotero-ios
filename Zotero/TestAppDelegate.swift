//
//  TestAppDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 14/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift

class TestAppDelegate: NSObject, UIApplicationDelegate {
    func applicationDidFinishLaunching(_ application: UIApplication) {
        if let logger = DDTTYLogger.sharedInstance {
            DDLog.add(logger)
        }
        dynamicLogLevel = .info
    }
}
