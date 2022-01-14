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

    private func removeFinishedUploadFiles() {
        let didDeleteFiles = UserDefaults.standard.bool(forKey: "DidDeleteFinishedUploadFiles")

        guard !didDeleteFiles && self.controllers.fileStorage.has(Files.uploads),
              let userControllers = self.controllers.userControllers else { return }

        do {
            let contents: [File] = try self.controllers.fileStorage.contentsOfDirectory(at: Files.uploads)

            guard !contents.isEmpty else { return }

            let backgroundUploads = userControllers.backgroundUploadObserver.context.uploads
            let webDavEnabled = userControllers.webDavController.sessionStorage.isEnabled
            var keysForUpload: Set<String> = []
            var filesToDelete: [File] = []

            if webDavEnabled {
                let forUploadResults = try userControllers.dbStorage.createCoordinator().perform(request: ReadAllItemsForUploadDbRequest())
                keysForUpload = Set(forUploadResults.map({ $0.key }))
            }

            for file in contents {
                if file.name.isEmpty && file.mimeType.isEmpty {
                    // Background Zotero upload
                    if !webDavEnabled && backgroundUploads.contains(where: { $0.fileUrl.lastPathComponent == file.relativeComponents.last }) {
                        // If file is being uploaded in background, don't delete
                        continue
                    }
                    filesToDelete.append(file)
                    continue
                }

                if file.ext == "zip" && !file.name.isEmpty {
                    // Background/foreground WebDAV upload
                    if webDavEnabled && (backgroundUploads.contains(where: { $0.fileUrl.deletingPathExtension().lastPathComponent == file.name }) || keysForUpload.contains(file.name)) {
                        // If file is being uploaded in background or queued to upload during sync, don't delete
                        continue
                    }
                    filesToDelete.append(file)
                }
            }

            for file in filesToDelete {
                try? self.controllers.fileStorage.remove(file)
            }

            UserDefaults.standard.setValue(true, forKey: "DidDeleteFinishedUploadFiles")
        } catch let error {
            DDLogError("AppDelegate: can't remove finished uploads - \(error)")
        }
    }

    private func updateCreatorSummaryFormat() {
        guard !UserDefaults.standard.bool(forKey: "DidUpdateCreatorSummaryFormat") else { return }

        guard let dbStorage = self.controllers.userControllers?.dbStorage else {
            // User logged out, don't need to update
            UserDefaults.standard.set(true, forKey: "DidUpdateCreatorSummaryFormat")
            return
        }

        do {
            try dbStorage.createCoordinator().perform(request: UpdateCreatorSummaryFormatDbRequest())
            UserDefaults.standard.set(true, forKey: "DidUpdateCreatorSummaryFormat")
        } catch let error {
            DDLogError("AppDelegate: can't update creator summary format - \(error)")
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

    private func setupExportDefaults() {
        if UserDefaults.standard.string(forKey: "QuickCopyLocaleId") != nil {
            // Value is already assigned, no need to do anything else.
            return
        }

        guard let localeIds = try? ExportLocaleReader.loadIds() else { return }

        let defaultLocale = localeIds.first(where: { $0.contains(Locale.current.identifier) }) ?? "en-US"
        UserDefaults.standard.setValue(defaultLocale, forKey: "QuickCopyLocaleId")
        UserDefaults.standard.setValue(defaultLocale, forKey: "ExportLocaleId")
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
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
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
        self.setupExportDefaults()

        #if PDFENABLED
        self.migratePdfSettings()
        #endif
        self.migrateItemsSortType()

        DispatchQueue.global(qos: .userInteractive).async {
            self.migrateFileStructure()
            self.removeFinishedUploadFiles()
            self.updateCreatorSummaryFormat()
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
        guard let userControllers = self.controllers.userControllers else {
            completionHandler()
            return
        }

        userControllers.backgroundUploadObserver.handleEventsForBackgroundURLSession(with: identifier, completionHandler: completionHandler)
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
