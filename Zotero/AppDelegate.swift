//
//  AppDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjack
import PSPDFKit
import RxSwift

extension Notification.Name {
    static let sessionChanged = Notification.Name(rawValue: "org.zotero.SessionChangedNotification")
}

@UIApplicationMain
class AppDelegate: UIResponder {

    private let disposeBag: DisposeBag = DisposeBag()

    var window: UIWindow?
    var controllers: Controllers!
    private var store: AppStore!

    // MARK: - Actions

    private func update(to state: AppState) {
        switch state {
        case .onboarding:
            let controller = OnboardingViewController(apiClient: self.controllers.apiClient,
                                                      secureStorage: self.controllers.secureStorage,
                                                      dbStorage: self.controllers.dbStorage)
            self.show(viewController: controller, animated: true)
        case .main:
            let controller = MainViewController(controllers: self.controllers)
            self.show(viewController: controller)
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

    @objc private func sessionChanged(_ notification: Notification) {
        let userId = notification.object as? Int
        self.store.handle(action: .change((userId != nil) ? .main : .onboarding))
        self.controllers.sessionChanged(userId: userId)

        if let syncController = self.controllers.userControllers?.syncController {
            syncController.startSync()
        }
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
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.sessionChanged(_:)),
                                               name: .sessionChanged, object: nil)
    }

    private func setupLogs() {
        #if DEBUG
        // Enable console logs only for debug mode
        DDLog.add(DDTTYLogger.sharedInstance)

        // Change to .info to enable server logging
        // Change to .warning/.error to disable server logging
        defaultDebugLevel = .info
        #else
        defaultDebugLevel = .error
        #endif
    }
}

extension AppDelegate: UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        PSPDFKit.setLicenseKey("WX2G0qNABNwhaL9hUMLRD4KgxL+VmVBszWG4PcoAWUZNTfDBMnje3gFxRoysA6wDlt5pDxAuEnsbPxZpmmGBDM3WFopE/mn0TWtHoeQm2ufzPmbcCraNaTfvhfhE6lDNFsoAahnWZRxt1XgadFEa7eNCc3T/PXEmSDATNMb+3IjBvcC7fkusDJASpZGkRr/VE8C1NNmd91p3mw7zGrwc0y5k81baQYJUXQbxA2azURPGdYbstShhofR8s9m3JciuwvNdyoqHCwZyV9m/RQGhGE2myZfV36JKmWH/hyc2Y2YqxYJSfgpyzEmm0pCU7KaX8skBZOvTYQHeh6DV55oDc78m3fxxk3pstNO1QKBuTJgd7gm3E3lBp0UC+J4EfAQPDNFwRSloRSX71gfEEM5+xBvcc6gajImPzZj+xJUNTG0oM5tfDibm8CJQ17IyyL3Y")
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
        self.controllers.userControllers?.syncController.startSync(isInitial: true)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
}
