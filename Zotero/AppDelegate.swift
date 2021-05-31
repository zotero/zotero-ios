//
//  AppDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RealmSwift
import SwiftUI

#if PDFENABLED
import PSPDFKit
import PSPDFKitUI
#endif

protocol SceneActivityCounter: AnyObject {
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

    /// This migration was created to move from "old" file structure (before build 120) to "new" one, where items are stored with their proper filenames.
    /// In `DidMigrateFileStructure` all downloaded items were moved. Items which were up for upload were forgotten, so `DidMigrateFileStructure2` was added to migrate also these items.
    /// TODO: - Remove after beta
    private func migrateFileStructure() {
        let didMigrateFileStructure = UserDefaults.standard.bool(forKey: "DidMigrateFileStructure")
        let didMigrateFileStructure2 = UserDefaults.standard.bool(forKey: "DidMigrateFileStructure2")

        guard !didMigrateFileStructure || !didMigrateFileStructure2 else { return }

        guard let dbStorage = self.controllers.userControllers?.dbStorage else {
            // If user is logget out, no need to migrate, DB is empty and files should be gone.
            UserDefaults.standard.setValue(true, forKey: "DidMigrateFileStructure")
            UserDefaults.standard.setValue(true, forKey: "DidMigrateFileStructure2")
            return
        }

        guard let coordinator = try? dbStorage.createCoordinator() else {
            // Can't load data, try again later
            return
        }

        // Migrate file structure
        if !didMigrateFileStructure && !didMigrateFileStructure2 {
            if let items = try? coordinator.perform(request: ReadAllDownloadedAndForUploadItemsDbRequest()) {
                self.migrateFileStructure(for: items)
            }
            UserDefaults.standard.setValue(true, forKey: "DidMigrateFileStructure")
            UserDefaults.standard.setValue(true, forKey: "DidMigrateFileStructure2")
        } else if !didMigrateFileStructure {
            if let items = try? coordinator.perform(request: ReadAllDownloadedItemsDbRequest()) {
                self.migrateFileStructure(for: items)
            }
            UserDefaults.standard.setValue(true, forKey: "DidMigrateFileStructure")
        } else if !didMigrateFileStructure2 {
            if let items = try? coordinator.perform(request: ReadAllItemsForUploadDbRequest()) {
                self.migrateFileStructure(for: items)
            }
            UserDefaults.standard.setValue(true, forKey: "DidMigrateFileStructure2")
        }

        NotificationCenter.default.post(name: .forceReloadItems, object: nil)
    }

    private func migrateFileStructure(for items: Results<RItem>) {
        for item in items {
            guard let type = AttachmentCreator.attachmentType(for: item, options: .light, fileStorage: nil, urlDetector: nil) else { continue }

            switch type {
            case .url: break
            case .file(_, _, _, let linkType) where (linkType == .embeddedImage || linkType == .linkedFile): break // Embedded images and linked files don't need to be checked.
            case .file(let filename, let contentType, _, let linkType):
                // Snapshots were stored based on new structure, no need to do anything.
                guard linkType != .importedUrl || contentType != "text/html", let libraryId = item.libraryId else { continue }

                let filenameParts = filename.split(separator: ".")
                let oldFile: File
                if filenameParts.count > 1, let ext = filenameParts.last.flatMap(String.init) {
                    oldFile = FileData(rootPath: Files.appGroupPath, relativeComponents: ["downloads", libraryId.folderName], name: item.key, ext: ext)
                } else {
                    oldFile = FileData(rootPath: Files.appGroupPath, relativeComponents: ["downloads", libraryId.folderName], name: item.key, contentType: contentType)
                }
                let newFile = Files.attachmentFile(in: libraryId, key: item.key, filename: filename, contentType: contentType)
                try? self.controllers.fileStorage.move(from: oldFile, to: newFile)
            }
        }
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

        DispatchQueue.global(qos: .userInteractive).async {
            self.migrateFileStructure()
        }

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
