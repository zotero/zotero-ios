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
    private var sessionCancellable: AnyCancellable?

    // MARK: - Actions

    private func showMainScreen(isLogged: Bool, animated: Bool) {
        if !isLogged {
            let view = OnboardingView()
                            .environment(\.apiClient, self.controllers.apiClient)
                            .environment(\.sessionController, self.controllers.sessionController)
            self.show(viewController: UIHostingController(rootView: view), animated: animated)
        } else {
            let controller = MainViewController(controllers: self.controllers)
            self.show(viewController: controller, animated: animated)

            self.controllers.userControllers?.syncScheduler.syncController.setConflictPresenter(controller)
        }
    }

    private func show(viewController: UIViewController?, animated: Bool = false) {
        let frame = UIScreen.main.bounds
        self.window = UIWindow(frame: frame)
        self.window?.makeKeyAndVisible()

        if !animated {
            self.window?.rootViewController = viewController
            return
        }

        viewController?.view.frame = frame
        UIView.animate(withDuration: 0.2) {
            self.window?.rootViewController = viewController
        }
    }

    // MARK: - Setups

    private func setupObservers() {
        self.sessionCancellable = self.controllers.sessionController.$isLoggedIn
                                                                    .receive(on: DispatchQueue.main)
                                                                    .dropFirst()
                                                                    .sink { [weak self] isLoggedIn in
                                                                        self?.showMainScreen(isLogged: isLoggedIn, animated: true)
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
        dynamicLogLevel = .error
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

        self.setupLogs()
        self.controllers = Controllers()
        self.controllers.crashReporter.start()
        self.controllers.crashReporter.processPendingReports()

        self.setupNavigationBarAppearance()

        self.setupObservers()

        self.showMainScreen(isLogged: self.controllers.sessionController.isLoggedIn, animated: false)

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        self.controllers.userControllers?.itemLocaleController.storeLocale()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        self.controllers.userControllers?.itemLocaleController.loadLocale()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        self.controllers.crashReporter.processPendingReports()
        self.controllers.schemaController.reloadSchemaIfNeeded()
        self.controllers.userControllers?.syncScheduler.requestFullSync()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
}
