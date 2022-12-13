//
//  Controllers.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

import CocoaLumberjackSwift
import RealmSwift
import RxSwift

/// Global controllers which don't need user session
final class Controllers {
    let sessionController: SessionController
    let apiClient: ApiClient
    let secureStorage: SecureStorage
    let fileStorage: FileStorage
    let schemaController: SchemaController
    let dragDropController: DragDropController
    let crashReporter: CrashReporter
    let debugLogging: DebugLogging
    let bundledDataStorage: DbStorage
    let translatorsAndStylesController: TranslatorsAndStylesController
    let annotationPreviewController: AnnotationPreviewController
    let urlDetector: UrlDetector
    let dateParser: DateParser
    let htmlAttributedStringConverter: HtmlAttributedStringConverter
    let idleTimerController: IdleTimerController
    let backgroundTaskController: BackgroundTaskController
    let lowPowerModeController: LowPowerModeController
    let userInitialized: PassthroughSubject<Result<Bool, Error>, Never>
    fileprivate let lastBuildNumber: Int?

    var userControllers: UserControllers?
    private var apiKey: String?
    private var sessionCancellable: AnyCancellable?
    private var didInitialize: Bool
    @UserDefault(key: "BaseKeyNeedsMigrationToPosition", defaultValue: true)
    fileprivate var needsBaseKeyMigration: Bool
    @UserDefault(key: "ChildItemsNeedFixingCollections", defaultValue: true)
    fileprivate var needsChildItemCollectionsFix: Bool
    @UserDefault(key: "EmptyNoteTitlesNeedFixing", defaultValue: true)
    fileprivate var needsEmptyNoteTitleFix: Bool

    private static func apiConfiguration(schemaVersion: Int) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["Zotero-API-Version": ApiConstants.version.description, "Zotero-Schema-Version": schemaVersion]
        configuration.sharedContainerIdentifier = AppGroup.identifier
        configuration.timeoutIntervalForRequest = ApiConstants.requestTimeout
        configuration.timeoutIntervalForResource = ApiConstants.resourceTimeout
        return configuration
    }

    init() {
        let schemaController = SchemaController()
        let fileStorage = FileStorageController()
        let apiClient = ZoteroApiClient(baseUrl: ApiConstants.baseUrlString, configuration: Controllers.apiConfiguration(schemaVersion: schemaController.version))

        let crashReporter = CrashReporter(apiClient: apiClient)
        // Start crash reporter as soon as possible to catch all crashes.
        crashReporter.start()
        let debugLogging = DebugLogging(apiClient: apiClient, fileStorage: fileStorage)
        // Start logging as soon as possible to catch all errors/warnings.
        debugLogging.startLoggingOnLaunchIfNeeded()

        let urlDetector = UrlDetector()
        let secureStorage = KeychainSecureStorage()
        let sessionController = SessionController(secureStorage: secureStorage, defaults: Defaults.shared)
        let bundledDataConfiguration = Database.bundledDataConfiguration(fileStorage: fileStorage)
        let bundledDataStorage = RealmDbStorage(config: bundledDataConfiguration)
        let translatorsAndStylesController = TranslatorsAndStylesController(apiClient: apiClient, bundledDataStorage: bundledDataStorage, fileStorage: fileStorage)
        let previewSize: CGSize

        #if PDFENABLED
        previewSize = CGSize(width: PDFReaderLayout.sidebarWidth, height: PDFReaderLayout.sidebarWidth)
        #else
        previewSize = CGSize()
        #endif

        self.bundledDataStorage = bundledDataStorage
        self.sessionController = sessionController
        self.apiClient = apiClient
        self.secureStorage = secureStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.dragDropController = DragDropController()
        self.crashReporter = crashReporter
        self.debugLogging = debugLogging
        self.translatorsAndStylesController = translatorsAndStylesController
        self.annotationPreviewController = AnnotationPreviewController(previewSize: previewSize, fileStorage: fileStorage)
        self.urlDetector = urlDetector
        self.dateParser = DateParser()
        self.htmlAttributedStringConverter = HtmlAttributedStringConverter()
        self.userInitialized = PassthroughSubject()
        self.lastBuildNumber = Defaults.shared.lastBuildNumber
        self.idleTimerController = IdleTimerController()
        self.backgroundTaskController = BackgroundTaskController()
        self.lowPowerModeController = LowPowerModeController()
        self.didInitialize = false

        Defaults.shared.lastBuildNumber = DeviceInfoProvider.buildNumber

        crashReporter.processPendingReports { [weak self] in
            self?.initializeSessionIfPossible()
            self?.startApp()
            self?.didInitialize = true
        }
    }

    // MARK: - App lifecycle

    func willEnterForeground() {
        guard self.didInitialize else { return }
        self.crashReporter.processPendingReports { [weak self] in
            self?.startApp()
        }
    }

    func didEnterBackground() {
        guard let controllers = self.userControllers else { return }
        controllers.disableSync(apiKey: nil)
    }

    func willTerminate() {
        guard let controllers = self.userControllers else { return }
        controllers.disableSync(apiKey: nil)
    }

    // MARK: - Actions

    private func startApp() {
        self.translatorsAndStylesController.update()
        guard let controllers = self.userControllers, let session = self.sessionController.sessionData else { return }
        controllers.enableSync(apiKey: session.apiToken)
    }

    private func initializeSessionIfPossible(failOnError: Bool = false) {
        do {
            // Try to initialize session
            try self.sessionController.initializeSession()
            // Start with initialized session
            self.update(with: self.sessionController.sessionData, isLogin: false, debugLogging: self.debugLogging)
            // Start observing further session changes
            self.startObservingSession()
        } catch let error {
            if !failOnError {
                // If this is first failure, start logging issues and wait for protected data
                self.debugLogging.start(type: .immediate)
                DDLogError("Controllers: session controller failed to initialize properly - \(error)")
                self.waitForProtectedDataAvailability { [weak self] in
                    self?.initializeSessionIfPossible(failOnError: true)
                }
                return
            }

            // If we already tried to wait for protected data availability and failed, we'll just show login screen and report an error.

            if self.debugLogging.isEnabled {
                // Stop debug logging
                DDLogError("Controllers: session controller failed to initialize properly - \(error)")
                self.debugLogging.stop(ignoreEmptyLogs: true, userId: 0, customAlertMessage: { L10n.loginDebug($0) })
            }

            // Show login screen
            self.update(with: nil, isLogin: false, debugLogging: self.debugLogging)
            // Start observing further session changes so that user can log in
            self.startObservingSession()
        }
    }

    private func waitForProtectedDataAvailability(numberOfChecks: Int = 0, completed: @escaping () -> Void) {
        let isAvailable = UIApplication.shared.isProtectedDataAvailable

        DDLogInfo("Controllers: waiting for protection availability: \(isAvailable); numberOfChecks: \(numberOfChecks)")

        if numberOfChecks > 0 && (isAvailable || numberOfChecks == 4) {
            completed()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
            self?.waitForProtectedDataAvailability(numberOfChecks: numberOfChecks + 1, completed: completed)
        }
    }

    private func startObservingSession() {
        self.sessionCancellable = self.sessionController.$sessionData
                                                        .receive(on: DispatchQueue.main)
                                                        .dropFirst()
                                                        .sink { [weak self] data in
                                                            guard let `self` = self else { return }
                                                            self.update(with: data, isLogin: true, debugLogging: self.debugLogging)
                                                        }
    }

    private func update(with data: SessionData?, isLogin: Bool, debugLogging: DebugLogging) {
        if let data = data {
            self.set(sessionData: data, isLogin: isLogin, debugLogging: debugLogging)
            self.apiKey = data.apiToken
        } else {
            self.clearSession()
            self.apiKey = nil
        }
    }

    private func set(sessionData data: SessionData, isLogin: Bool, debugLogging: DebugLogging) {
        do {
            // Set API auth token
            self.apiClient.set(authToken: ("Bearer " + data.apiToken), for: .zotero)

            // Start logging to catch user controller issues
            debugLogging.start(type: .immediate)

            // Initialize user controllers
            let controllers = try UserControllers(userId: data.userId, controllers: self)
            if isLogin {
                controllers.enableSync(apiKey: data.apiToken)
            }
            self.userControllers = controllers

            if !debugLogging.didStartFromLaunch {
                // If debug logging was started from launch by user, don't cancel ongoing logging. Otherwise cancel it, since nothing interesting happened during initialization.
                debugLogging.cancel()
            }

            // Show main screen
            self.userInitialized.send(.success(true))
        } catch let error {
            DDLogError("Controllers: can't create UserControllers - \(error)")

            let userId = Defaults.shared.userId

            // Initialization failed, clear everything
            self.apiClient.set(authToken: nil, for: .zotero)
            self.userControllers = nil
            // Stop observing session so that we don't get another event after reset
            self.sessionCancellable = nil
            self.sessionController.reset()
            // Re-start session observing
            self.startObservingSession()

            if let error = error as? Realm.Error, error.code == .fail {
                // Fatal error, remove db and let user log in again.
                let dbFile = Files.dbFile(for: userId)
                FileManager.default.clearDatabaseFiles(at: dbFile.createUrl())
            }

            debugLogging.stop(ignoreEmptyLogs: true, userId: userId, customAlertMessage: { L10n.migrationDebug($0) })

            self.userInitialized.send(.failure(error))
        }
    }

    private func clearSession() {
        let controllers = self.userControllers

        // `controllers.logout()` is called last so that the user is first redirected to login screen and then the DB is cleared. Otherwise the user would briefly see all data gone before being redirected.

        // Disable ongoing sync and unsubscribe from websocket
        controllers?.disableSync(apiKey: self.apiKey)
        // Cancel all downloads
        controllers?.fileDownloader.stop()
        // Cancel all background uploads
        controllers?.backgroundUploadObserver.cancelAllUploads()
        // Clear user controllers
        self.userControllers = nil
        // Clear API auth token
        self.apiClient.set(authToken: nil, for: .zotero)
        // Remove cache files
        try? self.fileStorage.remove(Files.cache)
        // Remove cached item jsons
        try? self.fileStorage.remove(Files.jsonCache)
        // Remove annotation preview cache
        try? self.fileStorage.remove(Files.annotationPreviews)
        // Remove interrupted upload files
        try? self.fileStorage.remove(Files.uploads)
        // Remove downloaded files
        try? self.fileStorage.remove(Files.downloads)
        // Report user logged out and show login screen
        self.userInitialized.send(.success(false))
        // Remove database
        controllers?.dbStorage.clear()
    }
}

/// Global controllers for logged in user
final class UserControllers {
    let syncScheduler: (SynchronizationScheduler & WebSocketScheduler)
    let changeObserver: ObjectUserChangeObserver
    let dbStorage: DbStorage
    let itemLocaleController: RItemLocaleController
    let backgroundUploadObserver: BackgroundUploadObserver
    let fileDownloader: AttachmentDownloader
    let remoteFileDownloader: RemoteAttachmentDownloader
    let webSocketController: WebSocketController
    let fileCleanupController: AttachmentFileCleanupController
    let citationController: CitationController
    let webDavController: WebDavController
    let customUrlController: CustomURLController
    private let isFirstLaunch: Bool
    private let lastBuildNumber: Int?
    private unowned let translatorsAndStylesController: TranslatorsAndStylesController
    private unowned let idleTimerController: IdleTimerController

    private static let schemaVersion: UInt64 = 9

    private var disposeBag: DisposeBag

    // MARK: - Lifecycle

    /// Instance is initialized on login or when app launches while user is logged in
    init(userId: Int, controllers: Controllers) throws {
        let dbStorage = try UserControllers.createDbStorage(for: userId, controllers: controllers)
        let webDavSession = SecureWebDavSessionStorage(secureStorage: controllers.secureStorage)
        let webDavController = WebDavControllerImpl(dbStorage: dbStorage, fileStorage: controllers.fileStorage, sessionStorage: webDavSession)
        let backgroundUploadContext = BackgroundUploaderContext()
        let backgroundUploadProcessor = BackgroundUploadProcessor(apiClient: controllers.apiClient, dbStorage: dbStorage, fileStorage: controllers.fileStorage, webDavController: webDavController)
        let backgroundUploadObserver = BackgroundUploadObserver(context: backgroundUploadContext, processor: backgroundUploadProcessor, backgroundTaskController: controllers.backgroundTaskController)
        let syncController = SyncController(userId: userId, apiClient: controllers.apiClient, dbStorage: dbStorage, fileStorage: controllers.fileStorage, schemaController: controllers.schemaController,
                                            dateParser: controllers.dateParser, backgroundUploaderContext: backgroundUploadContext, webDavController: webDavController, syncDelayIntervals: DelayIntervals.sync,
                                            conflictDelays: DelayIntervals.conflict)
        let fileDownloader = AttachmentDownloader(userId: userId, apiClient: controllers.apiClient, fileStorage: controllers.fileStorage, dbStorage: dbStorage, webDavController: webDavController)
        let webSocketController = WebSocketController(dbStorage: dbStorage, lowPowerModeController: controllers.lowPowerModeController)
        let fileCleanupController = AttachmentFileCleanupController(fileStorage: controllers.fileStorage, dbStorage: dbStorage)

        var isFirstLaunch = false
        try dbStorage.perform(on: .main, with: { [weak controllers] coordinator in
            isFirstLaunch = try coordinator.perform(request: InitializeCustomLibrariesDbRequest())
            try coordinator.perform(request: CleanupUnusedTags())
            if controllers?.needsBaseKeyMigration == true {
                // Fix "broken" fields which didn't correctly assign "baseKey" to "position" - #560
                try coordinator.perform(request: MigrateBaseKeysToPositionFieldDbAction())
                controllers?.needsBaseKeyMigration = false
            }
            if controllers?.needsChildItemCollectionsFix == true {
                try coordinator.perform(request: FixChildItemsWithCollectionsDbRequest())
                controllers?.needsChildItemCollectionsFix = false
            }
            if controllers?.needsEmptyNoteTitleFix == true {
                try coordinator.perform(request: FixNotesWithEmptyTitlesDbRequest())
                controllers?.needsEmptyNoteTitleFix = false
            }
        })

        self.isFirstLaunch = isFirstLaunch
        self.dbStorage = dbStorage
        self.syncScheduler = SyncScheduler(controller: syncController)
        self.webDavController = webDavController
        self.changeObserver = RealmObjectUserChangeObserver(dbStorage: dbStorage)
        self.itemLocaleController = RItemLocaleController(schemaController: controllers.schemaController, dbStorage: dbStorage)
        self.backgroundUploadObserver = backgroundUploadObserver
        self.fileDownloader = fileDownloader
        self.remoteFileDownloader = RemoteAttachmentDownloader(apiClient: controllers.apiClient, fileStorage: controllers.fileStorage)
        self.webSocketController = webSocketController
        self.fileCleanupController = fileCleanupController
        self.citationController = CitationController(stylesController: controllers.translatorsAndStylesController, fileStorage: controllers.fileStorage,
                                                     dbStorage: dbStorage, bundledDataStorage: controllers.bundledDataStorage)
        self.translatorsAndStylesController = controllers.translatorsAndStylesController
        self.idleTimerController = controllers.idleTimerController
        self.customUrlController = CustomURLController(dbStorage: dbStorage, fileStorage: controllers.fileStorage)
        self.lastBuildNumber = controllers.lastBuildNumber
        self.disposeBag = DisposeBag()
    }

    /// Connects to websocket to monitor changes and performs initial sync.
    fileprivate func enableSync(apiKey: String) {
        self.itemLocaleController.loadLocale()

        // Observe sync to enable/disable the device falling asleep
        self.syncScheduler.syncController.progressObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { `self`, progress in
                switch progress {
                case .aborted, .finished:
                    self.idleTimerController.enable()
                    if !Defaults.shared.didPerformFullSyncFix {
                        Defaults.shared.didPerformFullSyncFix = true
                    }

                case .starting:
                    self.idleTimerController.disable()
                default: break
                }
            })
            .disposed(by: self.disposeBag)

        // Observe local changes to start sync
        self.changeObserver.observable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] changedLibraries in
                self?.syncScheduler.request(sync: .normal, libraries: .specific(changedLibraries), applyDelay: true)
            })
            .disposed(by: self.disposeBag)

        // Observe remote changes to start sync/translator update
        self.webSocketController.observable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] change in
                switch change {
                case .translators:
                    self?.translatorsAndStylesController.updateFromRepo(type: .notification)
                case .library(let libraryId, _):
                    self?.syncScheduler.webSocketUpdate(libraryId: libraryId)
                }
            })
            .disposed(by: self.disposeBag)

        // Connect to websockets and start sync
        self.webSocketController.connect(apiKey: apiKey, completed: { [weak self] in
            guard let `self` = self else { return }
            // Call this before sync so that background uploads are updated and taken care of by sync if needed.
            self.backgroundUploadObserver.updateSessions()

            let type: SyncController.SyncType = Defaults.shared.didPerformFullSyncFix ? .normal : .full
            self.syncScheduler.request(sync: type, libraries: .all)
        })
    }

    /// Cancels ongoing sync and stops websocket connection.
    /// - parameter apiKey: If `apiKey` is provided, websocket sends and unsubscribe message before disconnecting.
    fileprivate func disableSync(apiKey: String?) {
        self.syncScheduler.cancelSync()
        self.webSocketController.disconnect(apiKey: apiKey)
        self.disposeBag = DisposeBag()
        self.itemLocaleController.storeLocale()
        self.backgroundUploadObserver.stopObservingShareExtensionChanges()
    }

    // MARK: - Helpers

    private class func createDbStorage(for userId: Int, controllers: Controllers) throws -> DbStorage {
        let file = Files.dbFile(for: userId)
        try controllers.fileStorage.createDirectories(for: file)
        return RealmDbStorage(config: Database.mainConfiguration(url: file.createUrl(), fileStorage: controllers.fileStorage))
    }
}
