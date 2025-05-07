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
    let pdfThumbnailController: PDFThumbnailController
    let urlDetector: UrlDetector
    let dateParser: DateParser
    let htmlAttributedStringConverter: HtmlAttributedStringConverter
    let idleTimerController: IdleTimerController
    let backgroundTaskController: BackgroundTaskController
    let lowPowerModeController: LowPowerModeController
    let uriConverter: ZoteroURIConverter
    let userInitialized: PassthroughSubject<Result<Bool, Error>, Never>
    fileprivate let lastBuildNumber: Int?

    var userControllers: UserControllers?
    private var apiKey: String?
    private var sessionCancellable: AnyCancellable?
    private var didInitialize: Bool
    @UserDefault(key: "BaseKeyNeedsMigrationToPosition", defaultValue: true)
    fileprivate var needsBaseKeyMigration: Bool
    fileprivate static let childItemCollectionsFixVersion: Int = 1
    @UserDefault(key: "ChildItemCollectionsFixCurrentVersion", defaultValue: 0)
    fileprivate var childItemCollectionsFixCurrentVersion: Int
    @UserDefault(key: "EmptyNoteTitlesNeedFixing", defaultValue: true)
    fileprivate var needsEmptyNoteTitleFix: Bool
    @UserDefault(key: "SchemaDatasetFieldIssueFix", defaultValue: true)
    fileprivate var needsSchemaDatasetFieldIssueFix: Bool
    @UserDefault(key: "TagOrderNeedsSync", defaultValue: true)
    fileprivate var tagOrderNeedsSync: Bool

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
        let previewSize = CGSize(width: PDFReaderLayout.sidebarWidth, height: PDFReaderLayout.sidebarWidth)

        self.bundledDataStorage = bundledDataStorage
        self.sessionController = sessionController
        self.apiClient = apiClient
        self.secureStorage = secureStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        dragDropController = DragDropController()
        self.crashReporter = crashReporter
        self.debugLogging = debugLogging
        self.translatorsAndStylesController = translatorsAndStylesController
        annotationPreviewController = AnnotationPreviewController(previewSize: previewSize, fileStorage: fileStorage)
        pdfThumbnailController = PDFThumbnailController(fileStorage: fileStorage)
        self.urlDetector = urlDetector
        dateParser = DateParser()
        htmlAttributedStringConverter = HtmlAttributedStringConverter()
        userInitialized = PassthroughSubject()
        lastBuildNumber = Defaults.shared.lastBuildNumber
        idleTimerController = IdleTimerController()
        backgroundTaskController = BackgroundTaskController()
        lowPowerModeController = LowPowerModeController()
        uriConverter = ZoteroURIConverter()
        didInitialize = false

        Defaults.shared.lastBuildNumber = DeviceInfoProvider.buildNumber

        crashReporter.processPendingReports { [weak self] in
            self?.initializeSessionIfPossible { success in
                if success {
                    self?.startApp()
                }
                self?.didInitialize = true
            }
        }
    }

    // MARK: - App lifecycle

    func willEnterForeground() {
        guard didInitialize else { return }
        crashReporter.processPendingReports { [weak self] in
            self?.startApp()
        }
    }

    func didEnterBackground() {
        userControllers?.disableSync(apiKey: nil)
    }

    func willTerminate() {
        userControllers?.disableSync(apiKey: nil)
    }

    // MARK: - Actions

    private func startApp() {
        translatorsAndStylesController.update()
        guard let userControllers, let session = sessionController.sessionData else { return }
        userControllers.enableSync(apiKey: session.apiToken)
    }

    private func initializeSessionIfPossible(failOnError: Bool = false, completion: @escaping (Bool) -> Void) {
        do {
            // Try to initialize session
            try sessionController.initializeSession()
            // Start with initialized session
            update(with: sessionController.sessionData, isLogin: false, debugLogging: debugLogging)
            // Start observing further session changes
            startObservingSession()
            completion(true)
        } catch let error {
            if !failOnError {
                // If this is first failure, start logging issues and wait for protected data
                debugLogging.start(type: .immediate)
                DDLogError("Controllers: session controller failed to initialize properly - \(error)")
                waitForProtectedDataAvailability { [weak self] in
                    self?.initializeSessionIfPossible(failOnError: true, completion: completion)
                }
                return
            }

            // If we already tried to wait for protected data availability and failed, we'll just show login screen and report an error.

            if debugLogging.isEnabled {
                // Stop debug logging
                DDLogError("Controllers: session controller failed to initialize properly - \(error)")
                debugLogging.stop(ignoreEmptyLogs: true, userId: 0, customAlertMessage: { L10n.loginDebug($0) })
            }

            // Show login screen
            update(with: nil, isLogin: false, debugLogging: debugLogging)
            // Start observing further session changes so that user can log in
            startObservingSession()
            completion(false)
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
        sessionCancellable = sessionController.$sessionData
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] data in
                guard let self else { return }
                update(with: data, isLogin: true, debugLogging: debugLogging)
            }
    }

    private func update(with data: SessionData?, isLogin: Bool, debugLogging: DebugLogging) {
        if let data {
            set(sessionData: data, isLogin: isLogin, debugLogging: debugLogging)
            apiKey = data.apiToken
        } else {
            clearSession()
            apiKey = nil
        }
    }

    private func set(sessionData data: SessionData, isLogin: Bool, debugLogging: DebugLogging) {
        do {
            // Set API auth token
            apiClient.set(authToken: ("Bearer " + data.apiToken))
            // Start logging to catch user controller issues
            debugLogging.start(type: .immediate)
            // Initialize user controllers
            let controllers = try UserControllers(userId: data.userId, controllers: self)
            if isLogin {
                controllers.enableSync(apiKey: data.apiToken)
            }
            userControllers = controllers

            if !debugLogging.didStartFromLaunch {
                // If debug logging was started from launch by user, don't cancel ongoing logging. Otherwise cancel it, since nothing interesting happened during initialization.
                debugLogging.cancel()
            }

            // Show main screen
            userInitialized.send(.success(true))
        } catch let error {
            DDLogError("Controllers: can't create UserControllers - \(error)")

            let userId = Defaults.shared.userId
            // Initialization failed, clear everything
            apiClient.set(authToken: nil)
            userControllers = nil
            // Stop observing session so that we don't get another event after reset
            sessionCancellable = nil
            sessionController.reset()
            // Re-start session observing
            startObservingSession()

            if let error = error as? Realm.Error, error.code == .fail {
                // Fatal error, remove db and let user log in again.
                let dbFile = Files.dbFile(for: userId)
                FileManager.default.clearDatabaseFiles(at: dbFile.createUrl())
            }

            debugLogging.stop(ignoreEmptyLogs: true, userId: userId, customAlertMessage: { L10n.migrationDebug($0) })

            userInitialized.send(.failure(error))
        }
    }

    private func clearSession() {
        // `controllers.logout()` is called last so that the user is first redirected to login screen and then the DB is cleared. Otherwise the user would briefly see all data gone before being redirected.
        // Disable ongoing sync and unsubscribe from websocket
        userControllers?.disableSync(apiKey: apiKey)
        // Cancel all downloads
        userControllers?.fileDownloader.cancelAll(invalidateSession: true)
        // Cancel all identifier lookups
        userControllers?.identifierLookupController.cancelAllLookups()
        // Cancel all remote downloads
        userControllers?.remoteFileDownloader.stop()
        // Cancel all background uploads
        userControllers?.backgroundUploadObserver.cancelAllUploads()
        // Cancel all Recognizer Tasks
        userControllers?.recognizerController.cancellAllTasks()
        // Cancel all PDF workers
        userControllers?.pdfWorkerController.cancellAllWorks()
        // Clear user controllers
        let dbStorage = userControllers?.dbStorage
        userControllers = nil
        // Clear API auth token
        apiClient.set(authToken: nil)
        // Remove cache files
        fileStorage.clearCache()
        // Report user logged out and show login screen
        userInitialized.send(.success(false))
        // Remove database
        dbStorage?.clear()
    }
}

/// Global controllers for logged in user
final class UserControllers {
    let autoEmptyController: AutoEmptyTrashController
    let syncScheduler: (SynchronizationScheduler & WebSocketScheduler)
    let changeObserver: ObjectUserChangeObserver
    let dbStorage: DbStorage
    let itemLocaleController: RItemLocaleController
    let backgroundUploadObserver: BackgroundUploadObserver
    let fileDownloader: AttachmentDownloader
    let remoteFileDownloader: RemoteAttachmentDownloader
    let identifierLookupController: IdentifierLookupController
    let pdfWorkerController: PDFWorkerController
    let recognizerController: RecognizerController
    let webSocketController: WebSocketController
    let fileCleanupController: AttachmentFileCleanupController
    let citationController: CitationController
    let webDavController: WebDavController
    let customUrlController: CustomURLController
    let fullSyncDebugger: FullSyncDebugger
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
        let fileDownloader = AttachmentDownloader(userId: userId, apiClient: controllers.apiClient, fileStorage: controllers.fileStorage, dbStorage: dbStorage, webDavController: webDavController)
        let syncController = SyncController(
            userId: userId,
            apiClient: controllers.apiClient,
            dbStorage: dbStorage,
            fileStorage: controllers.fileStorage,
            schemaController: controllers.schemaController,
            dateParser: controllers.dateParser,
            backgroundUploaderContext: backgroundUploadContext,
            webDavController: webDavController,
            attachmentDownloader: fileDownloader,
            syncDelayIntervals: DelayIntervals.sync,
            maxRetryCount: DelayIntervals.retry.count
        )
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
            if (controllers?.childItemCollectionsFixCurrentVersion ?? 0) < Controllers.childItemCollectionsFixVersion {
                try coordinator.perform(request: FixChildItemsWithCollectionsDbRequest())
                controllers?.childItemCollectionsFixCurrentVersion = Controllers.childItemCollectionsFixVersion
            }
            if controllers?.needsEmptyNoteTitleFix == true {
                try coordinator.perform(request: FixNotesWithEmptyTitlesDbRequest())
                controllers?.needsEmptyNoteTitleFix = false
            }
            if controllers?.needsSchemaDatasetFieldIssueFix == true {
                try coordinator.perform(request: FixSchemaIssueDbRequest())
                controllers?.needsSchemaDatasetFieldIssueFix = false
            }
            if controllers?.tagOrderNeedsSync == true {
                try coordinator.perform(request: ResetSettingsVersionDbRequest())
                controllers?.tagOrderNeedsSync = false
            }
        })

        autoEmptyController = AutoEmptyTrashController(dbStorage: dbStorage)
        self.isFirstLaunch = isFirstLaunch
        self.dbStorage = dbStorage
        syncScheduler = SyncScheduler(controller: syncController, retryIntervals: DelayIntervals.retry)
        self.webDavController = webDavController
        changeObserver = RealmObjectUserChangeObserver(dbStorage: dbStorage)
        itemLocaleController = RItemLocaleController(schemaController: controllers.schemaController, dbStorage: dbStorage)
        self.backgroundUploadObserver = backgroundUploadObserver
        self.fileDownloader = fileDownloader
        remoteFileDownloader = RemoteAttachmentDownloader(apiClient: controllers.apiClient, fileStorage: controllers.fileStorage)
        identifierLookupController = IdentifierLookupController(
            dbStorage: dbStorage,
            fileStorage: controllers.fileStorage,
            translatorsController: controllers.translatorsAndStylesController,
            schemaController: controllers.schemaController,
            dateParser: controllers.dateParser,
            remoteFileDownloader: remoteFileDownloader
        )
        pdfWorkerController = PDFWorkerController(fileStorage: controllers.fileStorage)
        recognizerController = RecognizerController(
            pdfWorkerController: pdfWorkerController,
            apiClient: controllers.apiClient,
            translatorsController: controllers.translatorsAndStylesController,
            schemaController: controllers.schemaController,
            dbStorage: dbStorage,
            dateParser: controllers.dateParser,
            fileStorage: controllers.fileStorage
        )
        self.webSocketController = webSocketController
        self.fileCleanupController = fileCleanupController
        citationController = CitationController(
            fileStorage: controllers.fileStorage,
            dbStorage: dbStorage,
            bundledDataStorage: controllers.bundledDataStorage
        )
        translatorsAndStylesController = controllers.translatorsAndStylesController
        fullSyncDebugger = FullSyncDebugger(syncScheduler: syncScheduler, debugLogging: controllers.debugLogging, sessionController: controllers.sessionController)
        idleTimerController = controllers.idleTimerController
        customUrlController = CustomURLController(dbStorage: dbStorage, fileStorage: controllers.fileStorage)
        lastBuildNumber = controllers.lastBuildNumber
        disposeBag = DisposeBag()
    }

    /// Connects to websocket to monitor changes and performs initial sync.
    fileprivate func enableSync(apiKey: String) {
        itemLocaleController.loadLocale()
        autoEmptyController.autoEmptyIfNeeded()

        // Reset Defaults.shared.didPerformFullSyncFix if needed
        DDLogInfo("Controllers: performFullSyncGuard: \(Defaults.shared.performFullSyncGuard); currentPerformFullSyncGuard: \(Defaults.currentPerformFullSyncGuard)")
        if Defaults.shared.performFullSyncGuard < Defaults.currentPerformFullSyncGuard {
            Defaults.shared.didPerformFullSyncFix = false
            Defaults.shared.performFullSyncGuard = Defaults.currentPerformFullSyncGuard
        } else {
            Defaults.shared.didPerformFullSyncFix = true
        }
        DDLogInfo("Controllers: didPerformFullSyncFix: \(Defaults.shared.didPerformFullSyncFix)")
        // Observe sync to enable/disable the device falling asleep
        // Skip first value that is observed during syncScheduler initialization, to avoid reseting didPerformFullSyncFix before the actual first sync occurs
        syncScheduler.inProgress
            .skip(1)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { inProgress in
                if !inProgress && !Defaults.shared.didPerformFullSyncFix {
                    Defaults.shared.didPerformFullSyncFix = true
                    DDLogInfo("Controllers: didPerformFullSyncFix: \(Defaults.shared.didPerformFullSyncFix)")
                }
            })
            .disposed(by: disposeBag)
        syncScheduler.syncController.progressObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] progress in
                guard let self else { return }
                switch progress {
                case .starting:
                    idleTimerController.startCustomIdleTimer()

                case .finished, .aborted:
                    idleTimerController.stopCustomIdleTimer()

                default:
                    idleTimerController.resetCustomTimer()
                }
            })
            .disposed(by: disposeBag)

        // Observe local changes to start sync
        changeObserver.observable
            .debounce(.seconds(3), scheduler: MainScheduler.instance)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] changedLibraries in
                self?.syncScheduler.request(sync: .normal, libraries: .specific(changedLibraries))
            })
            .disposed(by: disposeBag)

        // Observe remote changes to start sync/translator update
        webSocketController.observable
            .debounce(.seconds(3), scheduler: MainScheduler.instance)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] change in
                switch change {
                case .translators:
                    self?.translatorsAndStylesController.updateFromRepo(type: .notification)

                case .library(let libraryId, _):
                    self?.syncScheduler.webSocketUpdate(libraryId: libraryId)
                }
            })
            .disposed(by: disposeBag)

        // Connect to websockets and start sync
        webSocketController.connect(apiKey: apiKey, completed: { [weak self] in
            guard let self else { return }
            // Call this before sync so that background uploads are updated and taken care of by sync if needed.
            backgroundUploadObserver.updateSessions()

            let type: SyncController.Kind = Defaults.shared.didPerformFullSyncFix ? .normal : .full
            syncScheduler.request(sync: type, libraries: .all)
        })
    }

    /// Cancels ongoing sync and stops websocket connection.
    /// - parameter apiKey: If `apiKey` is provided, websocket sends and unsubscribe message before disconnecting.
    fileprivate func disableSync(apiKey: String?) {
        syncScheduler.cancelSync()
        webSocketController.disconnect(apiKey: apiKey)
        disposeBag = DisposeBag()
        itemLocaleController.storeLocale()
        backgroundUploadObserver.stopObservingShareExtensionChanges()
    }

    // MARK: - Helpers

    private class func createDbStorage(for userId: Int, controllers: Controllers) throws -> DbStorage {
        let file = Files.dbFile(for: userId)
        try controllers.fileStorage.createDirectories(for: file)
        return RealmDbStorage(config: Database.mainConfiguration(url: file.createUrl(), fileStorage: controllers.fileStorage))
    }
}
