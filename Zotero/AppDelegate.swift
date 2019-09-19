//
//  AppDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjack
import RxSwift
import SwiftUI

#if PDFENABLED
import PSPDFKit
#endif

extension Notification.Name {
    static let sessionChanged = Notification.Name(rawValue: "org.zotero.SessionChangedNotification")
}

class AppDelegate: UIResponder {

    private let disposeBag: DisposeBag = DisposeBag()

    var window: UIWindow?
    var controllers: Controllers!
    private var store: AppStore!
    private var didPresentInitialScreen = false

    // MARK: - Actions

    private func update(to state: AppState) {
        switch state {
        case .onboarding:
            let view = OnboardingView()
                            .environment(\.dbStorage, self.controllers.dbStorage)
                            .environment(\.apiClient, self.controllers.apiClient)
                            .environment(\.secureStorage, self.controllers.secureStorage)
            self.show(viewController: UIHostingController(rootView: view), animated: true)
        case .main:
            let controller = MainViewController(controllers: self.controllers)
            self.show(viewController: controller)

            self.controllers.userControllers?.syncScheduler.syncController.setConflictPresenter(controller)
            if self.didPresentInitialScreen {
                // request will be sent in didBecomeActive, this should be called only after login
                self.controllers.userControllers?.syncScheduler.requestFullSync()
            }
        }

        self.didPresentInitialScreen = true
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

    private func sessionChanged(to userId: Int?) {
        // This needs to be called before store change, because we need to have userControllers instance initialized
        // so that we can assign presenting controller for conflicts in store update(to:).
        self.controllers.sessionChanged(userId: userId)
        self.store.handle(action: .change((userId != nil) ? .main : .onboarding))
    }

    // MARK: - Setups

    private func setupStore() {
        self.store = AppStore(apiClient: self.controllers.apiClient,
                              secureStorage: self.controllers.secureStorage)
        self.store.state.asObservable()
                        .observeOn(MainScheduler.instance)
                        .subscribe(onNext: { [weak self] state in
                            self?.update(to: state)
                        })
                        .disposed(by: self.disposeBag)

    }

    private func setupObservers() {
        NotificationCenter.default.rx.notification(.sessionChanged)
                                     .observeOn(MainScheduler.instance)
                                     .subscribe(onNext: { [weak self] notification in
                                         self?.sessionChanged(to: (notification.object as? Int))
                                     })
                                     .disposed(by: self.disposeBag)
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
        self.setupObservers()
        self.setupStore()

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        self.controllers.schemaController.reloadSchemaIfNeeded()
        self.controllers.userControllers?.syncScheduler.requestFullSync()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
}
