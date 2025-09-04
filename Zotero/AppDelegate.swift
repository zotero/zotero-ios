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

import PSPDFKit
import PSPDFKitUI

protocol SceneActivityCounter: AnyObject {
    func sceneWillEnterForeground()
    func sceneDidEnterBackground()
}

final class AppDelegate: UIResponder {
    var controllers: Controllers!
    private var foregroundSceneCount = 0

    // MARK: - Migration

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

    private func migrateActiveColor() {
        guard let activeColorHex = UserDefaults.zotero.object(forKey: "PDFReaderState.activeColor") as? String else { return }
        Defaults.shared.highlightColorHex = activeColorHex
        Defaults.shared.noteColorHex = activeColorHex
        Defaults.shared.squareColorHex = activeColorHex
        Defaults.shared.inkColorHex = activeColorHex
        UserDefaults.zotero.removeObject(forKey: "PDFReaderState.activeColor")
    }

    private func migrateItemsSortType() {
        guard let sortTypeData = UserDefaults.standard.data(forKey: "ItemsSortType"),
              let unarchived = try? PropertyListDecoder().decode(ItemsSortType.self, from: sortTypeData) else { return }

        Defaults.shared.itemsSortType = unarchived
        UserDefaults.standard.removeObject(forKey: "ItemsSortType")
    }

    private func readAttachmentTypes<Request: DbResponseRequest>(for request: Request, dbStorage: DbStorage, queue: DispatchQueue) throws -> [(String, LibraryIdentifier, Attachment.Kind)] where Request.Response == Results<RItem> {
        var types: [(String, LibraryIdentifier, Attachment.Kind)] = []

        try dbStorage.perform(on: queue, with: { coordinator in
            let items = try coordinator.perform(request: request)

            types = items.compactMap({ item -> (String, LibraryIdentifier, Attachment.Kind)? in
                guard let type = AttachmentCreator.attachmentType(for: item, options: .light, fileStorage: nil, urlDetector: nil), let libraryId = item.libraryId else { return nil }
                return (item.key, libraryId, type)
            })

            coordinator.invalidate()
        })

        return types
    }

    private func removeFinishedUploadFiles(queue: DispatchQueue) {
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
                let forUploadResults = try userControllers.dbStorage.perform(request: ReadAllItemsForUploadDbRequest(), on: queue)
                keysForUpload = Set(forUploadResults.map({ $0.key }))
                forUploadResults.first?.realm?.invalidate()
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

    private func updateCreatorSummaryFormat(queue: DispatchQueue) {
        guard !UserDefaults.standard.bool(forKey: "DidUpdateCreatorSummaryFormat") else { return }

        guard let dbStorage = self.controllers.userControllers?.dbStorage else {
            // User logged out, don't need to update
            UserDefaults.standard.set(true, forKey: "DidUpdateCreatorSummaryFormat")
            return
        }

        do {
            try dbStorage.perform(request: UpdateCreatorSummaryFormatDbRequest(), on: queue)
            UserDefaults.standard.set(true, forKey: "DidUpdateCreatorSummaryFormat")
        } catch let error {
            DDLogError("AppDelegate: can't update creator summary format - \(error)")
        }
    }

    private func endPendingItemCreations(queue: DispatchQueue) {
        guard let dbStorage = controllers.userControllers?.dbStorage else { return }
        try? dbStorage.perform(request: EndPendingItemCreationsDbRequest(), on: queue)
        do {
            try dbStorage.perform(request: EndPendingItemCreationsDbRequest(), on: queue)
        } catch let error {
            DDLogError("AppDelegate: can't ending creation for pending items - \(error)")
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
        if #unavailable(iOS 26.0.0) {
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
        if #available(iOS 26.0, *) {
            // TODO: - Remove when no longer necessary (hopefully when Xcode 26 is out of beta)
            nw_tls_create_options()
        }
        if let key = Licenses.shared.pspdfkitKey {
            PSPDFKit.SDK.setLicenseKey(key)
        }
        DDLogInfo("AppDelegate: clearPSPDFKitCacheGuard: \(Defaults.shared.clearPSPDFKitCacheGuard); currentClearPSPDFKitCacheGuard: \(Defaults.currentClearPSPDFKitCacheGuard)")
        if Defaults.shared.clearPSPDFKitCacheGuard < Defaults.currentClearPSPDFKitCacheGuard {
            PSPDFKit.SDK.shared.cache.clear()
            DDLogInfo("AppDelegate: did clear PSPDFKit cache")
            Defaults.shared.clearPSPDFKitCacheGuard = Defaults.currentClearPSPDFKitCacheGuard
        }
        PSPDFKit.SDK.shared.styleManager.setLastUsedValue(AnnotationsConfig.imageAnnotationLineWidth,
                                                          forProperty: "lineWidth",
                                                          forKey: PSPDFKit.Annotation.ToolVariantID(tool: .square))

        self.setupLogs()
        self.controllers = Controllers()
        self.setupAppearance()
        self.setupExportDefaults()

        self.migrateActiveColor()
        self.migratePdfSettings()
        self.migrateItemsSortType()

        let queue = DispatchQueue(label: "org.zotero.AppDelegateMigration", qos: .userInitiated)
        DispatchQueue.main.async {
            queue.async {
                self.removeFinishedUploadFiles(queue: queue)
                self.updateCreatorSummaryFormat(queue: queue)
                self.endPendingItemCreations(queue: queue)
            }
        }

        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        self.controllers.didEnterBackground()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        self.controllers.willEnterForeground()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        self.controllers.willTerminate()
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard let userControllers = self.controllers.userControllers else {
            completionHandler()
            return
        }

        guard !userControllers.fileDownloader.handleEventsForBackgroundURLSession(with: identifier, completionHandler: completionHandler) else { return }
        userControllers.backgroundUploadObserver.handleEventsForBackgroundURLSession(with: identifier, completionHandler: completionHandler)
    }

    func application(_ application: UIApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool {
        return true
    }

    func application(_ application: UIApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool {
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
