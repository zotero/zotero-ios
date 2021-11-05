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
    let userInitialized: PassthroughSubject<Result<Bool, Error>, Never>
    let idleTimerController: IdleTimerController
    fileprivate let lastBuildNumber: Int?

    var userControllers: UserControllers?
    private var apiKey: String?
    private var sessionCancellable: AnyCancellable?

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

        Defaults.shared.lastBuildNumber = DeviceInfoProvider.buildNumber
        self.startObservingSession()
        self.update(with: self.sessionController.sessionData, isLogin: false, debugLogging: debugLogging)
    }

    func willEnterForeground() {
        self.crashReporter.processPendingReports()
        self.translatorsAndStylesController.update()

        guard let controllers = self.userControllers, let session = self.sessionController.sessionData else { return }
        controllers.enableSync(apiKey: session.apiToken)
    }

    func didEnterBackground() {
        guard let controllers = self.userControllers else { return }
        controllers.disableSync(apiKey: nil)
    }
    
    func willTerminate() {
        guard let controllers = self.userControllers else { return }
        controllers.disableSync(apiKey: nil)
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
            self.initializeSession(with: data, isLogin: isLogin, debugLogging: debugLogging)
            self.apiKey = data.apiToken
        } else {
            self.clearSession()
            self.apiKey = nil
            // Clear cache files on logout
            try? self.fileStorage.remove(Files.cache)
        }
    }

    private func initializeSession(with data: SessionData, isLogin: Bool, debugLogging: DebugLogging) {
        do {
            self.apiClient.set(authToken: data.apiToken)

            debugLogging.start(type: .immediate)

            let controllers = try UserControllers(userId: data.userId, controllers: self)
            if isLogin {
                controllers.enableSync(apiKey: data.apiToken)
            }
            self.userControllers = controllers

            if !debugLogging.didStartFromLaunch {
                // If debug logging was started from launch by user, don't cancel ongoing logging. Otherwise cancel it, since nothing interesting happen during initialization.
                debugLogging.cancel()
            }

            self.userInitialized.send(.success(true))
        } catch let error {
            DDLogError("Controllers: can't create UserControllers - \(error)")

            // Initialization failed, clear everything
            self.apiClient.set(authToken: nil)
            self.userControllers = nil
            // Stop observing session so that we don't get another event after reset
            self.sessionCancellable = nil
            self.sessionController.reset()
            // Re-start session observing
            self.startObservingSession()

            debugLogging.stop(ignoreEmptyLogs: true, customAlertMessage: { L10n.migrationDebug($0) })

            self.userInitialized.send(.failure(error))
        }
    }

    private func clearSession() {
        let controllers = self.userControllers

        // `controllers.logout()` is called last so that the user is first redirected to login screen and then the DB is cleared. Otherwise the user would briefly see all data gone before being redirected.

        // Disable ongoing sync and unsubscribe from websocket
        controllers?.disableSync(apiKey: self.apiKey)
        // Clear session and controllers
        self.apiClient.set(authToken: nil)
        self.userControllers = nil
        // Report user logged out
        self.userInitialized.send(.success(false))
        // Clear data
        controllers?.logout()
    }
}

/// Global controllers for logged in user
final class UserControllers {
    let syncScheduler: (SynchronizationScheduler & WebSocketScheduler)
    let changeObserver: ObjectUserChangeObserver
    let dbStorage: DbStorage
    let itemLocaleController: RItemLocaleController
    let backgroundUploader: BackgroundUploader
    let fileDownloader: AttachmentDownloader
    let webSocketController: WebSocketController
    let fileCleanupController: AttachmentFileCleanupController
    let citationController: CitationController
    let webDavController: WebDavController
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
        let backgroundUploadProcessor = BackgroundUploadProcessor(apiClient: controllers.apiClient, dbStorage: dbStorage, fileStorage: controllers.fileStorage, webDavController: webDavController)
        let backgroundUploader = BackgroundUploader(uploadProcessor: backgroundUploadProcessor, schemaVersion: controllers.schemaController.version)
        let syncController = SyncController(userId: userId, apiClient: controllers.apiClient, dbStorage: dbStorage, fileStorage: controllers.fileStorage, schemaController: controllers.schemaController,
                                            dateParser: controllers.dateParser, backgroundUploader: backgroundUploader, webDavController: webDavController, syncDelayIntervals: DelayIntervals.sync,
                                            conflictDelays: DelayIntervals.conflict)
        let fileDownloader = AttachmentDownloader(userId: userId, apiClient: controllers.apiClient, fileStorage: controllers.fileStorage, dbStorage: dbStorage, webDavController: webDavController)
        let webSocketController = WebSocketController(dbStorage: dbStorage)
        let fileCleanupController = AttachmentFileCleanupController(fileStorage: controllers.fileStorage, dbStorage: dbStorage)

        self.dbStorage = dbStorage
        self.syncScheduler = SyncScheduler(controller: syncController)
        self.webDavController = webDavController
        self.changeObserver = RealmObjectUserChangeObserver(dbStorage: dbStorage)
        self.itemLocaleController = RItemLocaleController(schemaController: controllers.schemaController, dbStorage: dbStorage)
        self.backgroundUploader = backgroundUploader
        self.fileDownloader = fileDownloader
        self.webSocketController = webSocketController
        self.fileCleanupController = fileCleanupController
        self.citationController = CitationController(stylesController: controllers.translatorsAndStylesController, fileStorage: controllers.fileStorage,
                                                     dbStorage: dbStorage, bundledDataStorage: controllers.bundledDataStorage)
        self.translatorsAndStylesController = controllers.translatorsAndStylesController
        self.idleTimerController = controllers.idleTimerController
        self.lastBuildNumber = controllers.lastBuildNumber
        self.disposeBag = DisposeBag()

        let coordinator = try dbStorage.createCoordinator()
        self.isFirstLaunch = try coordinator.perform(request: InitializeCustomLibrariesDbRequest())
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
                self?.syncScheduler.requestNormalSync(for: changedLibraries)
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
            self.syncScheduler.request(syncType: self.requiresFullSync ? .full : .normal)
        })
    }

    private var requiresFullSync: Bool {
        // Check whether the app was not just launched for the first time.
        guard !self.isFirstLaunch else { return false }
        // Check last build number, if it's `nil`, it hasn't been stored previously, which means that it's older than the first build, which stores it and needs a full sync for previous bug fixes.
        guard let buildNumber = self.lastBuildNumber else { return true }
        return buildNumber < 102
    }

    /// Cancels ongoing sync and stops websocket connection.
    /// - parameter apiKey: If `apiKey` is provided, websocket sends and unsubscribe message before disconnecting.
    fileprivate func disableSync(apiKey: String?) {
        self.syncScheduler.cancelSync()
        self.webSocketController.disconnect(apiKey: apiKey)
        self.disposeBag = DisposeBag()
        self.itemLocaleController.storeLocale()
    }

    fileprivate func logout() {
        // Clear DB storage
        self.dbStorage.clear()
        // Cancel all pending background uploads
        self.backgroundUploader.cancel()
    }

    // MARK: - Helpers

    private class func createDbStorage(for userId: Int, controllers: Controllers) throws -> DbStorage {
        let file = Files.dbFile(for: userId)
        try controllers.fileStorage.createDirectories(for: file)
        return RealmDbStorage(config: Database.mainConfiguration(url: file.createUrl(), fileStorage: controllers.fileStorage))
    }
}
