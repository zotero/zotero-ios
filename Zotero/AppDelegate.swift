//
//  AppDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import SwiftUI

#if PDFENABLED
import PSPDFKit
import PSPDFKitUI
#endif

protocol SceneActivityCounter: class {
    func sceneWillEnterForeground()
    func sceneDidEnterBackground()
}

final class AppDelegate: UIResponder {
    var controllers: Controllers!
    private var foregroundSceneCount = 0

    // MARK: - Migration

    #if PDFENABLED
    private func migratePdfSettings() {
        let rawScrollDirection = UserDefaults.standard.value(forKey: "PdfReader.ScrollDirection") as? UInt
        let rawPageTransition = UserDefaults.standard.value(forKey: "PdfReader.PageTransition") as? UInt

        guard rawScrollDirection != nil || rawPageTransition != nil else { return }

        var settings = Defaults.shared.pdfSettings
        settings.direction = rawScrollDirection.flatMap({ ScrollDirection(rawValue: $0) }) ?? settings.direction
        settings.transition = rawPageTransition.flatMap({ PageTransition(rawValue: $0) }) ?? settings.transition
        Defaults.shared.pdfSettings = settings

        UserDefaults.standard.removeObject(forKey: "PdfReader.ScrollDirection")
        UserDefaults.standard.removeObject(forKey: "PdfReader.PageTransition")
    }
    #endif

    private func migrateItemsSortType() {
        guard let sortTypeData = UserDefaults.standard.data(forKey: "ItemsSortType"),
              let unarchived = try? PropertyListDecoder().decode(ItemsSortType.self, from: sortTypeData) else { return }

        Defaults.shared.itemsSortType = unarchived
        UserDefaults.standard.removeObject(forKey: "ItemsSortType")
    }

    // MARK: - Setups

    private func setupLogs() {
        #if DEBUG
        // Enable console logs only for debug mode
        let logger = DDOSLogger.sharedInstance
        logger.logFormatter = DebugLogFormatter(targetName: "Zotero")
        DDLog.add(logger)
        dynamicLogLevel = .debug
        #else
        // Change to .info to enable server logging
        // Change to .warning/.error to disable server logging
        dynamicLogLevel = .info
        #endif
    }

    private func setupAppearance() {
        // Navigation bars
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().tintColor = Asset.Colors.zoteroBlue.color
        // Toolbars
        UIToolbar.appearance().tintColor = Asset.Colors.zoteroBlue.color
        // Buttons
        UIButton.appearance().tintColor = Asset.Colors.zoteroBlue.color
        // Search bar
        UISearchBar.appearance().tintColor = Asset.Colors.zoteroBlue.color
    }
}

extension AppDelegate: SceneActivityCounter {
    func sceneDidEnterBackground() {
        self.foregroundSceneCount -= 1

        if self.foregroundSceneCount == 0 {
            self.applicationDidEnterBackground(UIApplication.shared)
        }
    }

    func sceneWillEnterForeground() {
        if self.foregroundSceneCount == 0 {
            self.applicationWillEnterForeground(UIApplication.shared)
        }

        self.foregroundSceneCount += 1
    }
}

extension AppDelegate: UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if PDFENABLED
        if let key = Licenses.shared.pspdfkitKey {
            PSPDFKit.SDK.setLicenseKey(key)
        }
        PSPDFKit.SDK.shared.styleManager.setLastUsedValue(AnnotationsConfig.imageAnnotationLineWidth,
                                                          forProperty: "lineWidth",
                                                          forKey: PSPDFKit.Annotation.ToolVariantID(tool: .square))
        #endif

        self.setupLogs()
        self.controllers = Controllers()
        self.setupAppearance()

        #if PDFENABLED
        self.migratePdfSettings()
        #endif
        self.migrateItemsSortType()

        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        self.controllers.didEnterBackground()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        self.controllers.willEnterForeground()
        NotificationCenter.default.post(name: .willEnterForeground, object: nil)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        self.controllers.willTerminate()
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        let controllers = self.controllers ?? Controllers()
        if let uploader = controllers.userControllers?.backgroundUploader {
            uploader.backgroundCompletionHandler = completionHandler
        } else {
            completionHandler()
        }
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
