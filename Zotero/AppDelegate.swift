//
//  AppDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

extension Notification.Name {
    static let sessionChanged = Notification.Name(rawValue: "org.zotero.SessionChangedNotification")
}

@UIApplicationMain
class AppDelegate: UIResponder {

    var window: UIWindow?
    var controllers: Controllers!
    private var store: AppStore!
    private var storeToken: StoreSubscriptionToken?

    // MARK: - Actions

    private func update(to state: AppState) {
        switch state {
        case .onboarding:
            let controller = OnboardingViewController(apiClient: self.controllers.apiClient,
                                                      secureStorage: self.controllers.secureStorage,
                                                      dbStorage: self.controllers.dbStorage)
            self.show(viewController: controller, animated: true)
        case .main:
            let controller = UISplitViewController()
            let mainController = CollectionsViewController()
            let mainNavigationController = UINavigationController(rootViewController: mainController)
            let sideController = ItemsViewController()
            let sideNavigationController = UINavigationController(rootViewController: sideController)
            controller.viewControllers = [mainNavigationController, sideNavigationController]
            self.show(viewController: controller)

            if let userId = (try? self.controllers.dbStorage.createCoordinator())?.perform(request: ReadUserDbRequest())?.identifier {
                let request = GroupVersionsRequest(userId: userId)
                self.controllers.apiClient.send(request: request) { _ in }
            }
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
        guard let isLoggedIn = notification.object as? Bool else { return }
        self.store.handle(action: .change(isLoggedIn ? .main : .onboarding))
    }

    // MARK: - Setups

    private func setupStore() {
        self.store = AppStore(apiClient: self.controllers.apiClient,
                              secureStorage: self.controllers.secureStorage)
        self.storeToken = self.store.subscribe(action: { [weak self] newState in
            self?.update(to: newState)
        })
    }

    private func setupControllers() {
        let secureStorage = KeychainSecureStorage()
        let apiClient = ZoteroApiClient(baseUrl: ApiConstants.baseUrlString,
                                        headers: ["Zotero-API-Version": ApiConstants.version.description])
        apiClient.set(authToken: secureStorage.apiToken)

        let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .allDomainsMask, true).first ?? "/"
        var url = URL(fileURLWithPath: path)
        url.appendPathComponent("maindb")
        url.appendPathExtension("realm")
        let dbStorage = RealmDbStorage(url: url)

        self.controllers = Controllers(apiClient: apiClient,
                                       secureStorage: secureStorage,
                                       dbStorage: dbStorage)
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.sessionChanged(_:)),
                                               name: .sessionChanged, object: nil)
    }
}

extension AppDelegate: UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        self.setupControllers()
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
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
}
