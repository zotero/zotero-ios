//
//  AppDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import UIKit

import CocoaLumberjack
import SwiftUI

#if PDFENABLED
import PSPDFKit
#endif

class AppDelegate: UIResponder {
    var window: UIWindow?
    var controllers: Controllers!
    private var coordinator: AppCoordinator!
    private var sessionCancellable: AnyCancellable?

    // MARK: - Setups

    private func setupObservers() {
        self.sessionCancellable = self.controllers.sessionController.$isLoggedIn
                                                                    .receive(on: DispatchQueue.main)
                                                                    .dropFirst()
                                                                    .sink { [weak self] isLoggedIn in
                                                                        self?.coordinator.showMainScreen(isLoggedIn: isLoggedIn)
                                                                    }
    }

    private func setupLogs() {
        #if DEBUG
        // Enable console logs only for debug mode
        DDLog.add(DDTTYLogger.sharedInstance)

        // Change to .info to enable server logging
        // Change to .warning/.error to disable server logging
        dynamicLogLevel = .info
        #else
        dynamicLogLevel = .off
        #endif
    }

    private func setupNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}

extension AppDelegate: UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if PDFENABLED
        if let key = Licenses.shared.pspdfkitKey {
            PSPDFKit.setLicenseKey(key)
        }
        #endif

        // Setup logging
        self.setupLogs()
        // Setup controllers
        self.controllers = Controllers()
        // Setup window and appearance
        self.window = UIWindow(frame: UIScreen.main.bounds)
        self.window?.makeKeyAndVisible()
        self.setupNavigationBarAppearance()
        // Setup app coordinator and present initial screen
        self.coordinator = AppCoordinator(window: self.window, controllers: self.controllers)
        self.coordinator.start()
        // Start observing changes
        self.setupObservers()
        // `willEnterForegound` is not called after launching the app for the first time.
        self.controllers.willEnterForeground()

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        self.controllers.didEnterBackground()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        self.controllers.willEnterForeground()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
    }

    func applicationWillTerminate(_ application: UIApplication) {
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        let controllers = self.controllers ?? Controllers()
        if let uploader = controllers.userControllers?.backgroundUploader {
            uploader.backgroundCompletionHandler = completionHandler
        } else {
            completionHandler()
        }
    }
}
