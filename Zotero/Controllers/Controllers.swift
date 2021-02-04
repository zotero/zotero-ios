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
class Controllers {
    let sessionController: SessionController
    let apiClient: ApiClient
    let secureStorage: SecureStorage
    let fileStorage: FileStorage
    let schemaController: SchemaController
    let dragDropController: DragDropController
    let crashReporter: CrashReporter
    let debugLogging: DebugLogging
    let translatorsController: TranslatorsController
    let annotationPreviewController: AnnotationPreviewController
    let urlDetector: UrlDetector
    let dateParser: DateParser
    let fileCleanupController: AttachmentFileCleanupController
    let htmlAttributedStringConverter: HtmlAttributedStringConverter
    let userInitialized: PassthroughSubject<Result<Bool, Error>, Never>

    var userControllers: UserControllers?
    // Stores initial error when initializing `UserControllers`. It's needed in case the error happens on app launch.
    // The event sent through `userInitialized` publisher is not received by scene, because this happens in AppDelegate `didFinishLaunchingWithOptions`.
    var userControllerError: Error?
    private var apiKey: String?
    private var sessionCancellable: AnyCancellable?

    init() {
        let schemaController = SchemaController()

        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["Zotero-API-Version": ApiConstants.version.description,
                                               "Zotero-Schema-Version": schemaController.version]
        configuration.sharedContainerIdentifier = AppGroup.identifier

        let fileStorage = FileStorageController()
        let debugLogging = DebugLogging(fileStorage: fileStorage)
        // Start logging as soon as possible to catch all errors/warnings.
        debugLogging.startLoggingOnLaunchIfNeeded()
        let apiClient = ZoteroApiClient(baseUrl: ApiConstants.baseUrlString, configuration: configuration)
        let crashReporter = CrashReporter(apiClient: apiClient)
        // Start crash reporter as soon as possible to catch all crashes.
        crashReporter.start()
        let secureStorage = KeychainSecureStorage()
        let sessionController = SessionController(secureStorage: secureStorage, defaults: Defaults.shared)
        let translatorsController = TranslatorsController(apiClient: apiClient,
                                                          indexStorage: RealmDbStorage(config: Database.translatorConfiguration),
                                                          fileStorage: fileStorage)
        let fileCleanupController = AttachmentFileCleanupController(fileStorage: fileStorage)
        let previewSize = CGSize(width: PDFReaderLayout.sidebarWidth, height: PDFReaderLayout.sidebarWidth)

        self.sessionController = sessionController
        self.apiClient = apiClient
        self.secureStorage = secureStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.dragDropController = DragDropController()
        self.crashReporter = crashReporter
        self.debugLogging = debugLogging
        self.translatorsController = translatorsController
        self.annotationPreviewController = AnnotationPreviewController(previewSize: previewSize, fileStorage: fileStorage)
        self.urlDetector = UrlDetector()
        self.dateParser = DateParser()
        self.fileCleanupController = fileCleanupController
        self.htmlAttributedStringConverter = HtmlAttributedStringConverter()
        self.userInitialized = PassthroughSubject()

        self.startObservingSession()
        self.update(with: self.sessionController.sessionData, isLogin: false)
    }

    func willEnterForeground() {
        self.crashReporter.processPendingReports()
        self.translatorsController.update()

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
                                                            self?.update(with: data, isLogin: true)
                                                        }
    }

    private func update(with data: SessionData?, isLogin: Bool) {
        if let data = data {
            self.initializeSession(with: data, isLogin: isLogin)
            self.apiKey = data.apiToken
        } else {
            self.clearSession()
            self.apiKey = nil
            // Clear cache files on logout
            try? self.fileStorage.remove(Files.cache)
        }
    }

    private func initializeSession(with data: SessionData, isLogin: Bool) {
        do {
            self.apiClient.set(authToken: data.apiToken)

            let controllers = try UserControllers(userId: data.userId, controllers: self)
            if isLogin {
                controllers.enableSync(apiKey: data.apiToken)
            }
            self.userControllers = controllers

            self.userControllerError = nil
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

            self.userControllerError = error
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
        self.userControllerError = nil
        // Report user logged out
        self.userInitialized.send(.success(false))
        // Clear data
        controllers?.logout()
    }
}

/// Global controllers for logged in user
class UserControllers {
    let syncScheduler: SynchronizationScheduler
    let changeObserver: ObjectChangeObserver
    let dbStorage: DbStorage
    let itemLocaleController: RItemLocaleController
    let backgroundUploader: BackgroundUploader
    let fileDownloader: FileDownloader
    let webSocketController: WebSocketController

    private static let schemaVersion: UInt64 = 9

    private var disposeBag: DisposeBag

    // MARK: - Lifecycle

    /// Instance is initialized on login or when app launches while user is logged in
    init(userId: Int, controllers: Controllers) throws {
        let dbStorage = try UserControllers.createDbStorage(for: userId, controllers: controllers)
        let backgroundUploadProcessor = BackgroundUploadProcessor(apiClient: controllers.apiClient,
                                                                  dbStorage: dbStorage,
                                                                  fileStorage: controllers.fileStorage)
        let backgroundUploader = BackgroundUploader(uploadProcessor: backgroundUploadProcessor, schemaVersion: controllers.schemaController.version)

        let syncController = SyncController(userId: userId,
                                            apiClient: controllers.apiClient,
                                            dbStorage: dbStorage,
                                            fileStorage: controllers.fileStorage,
                                            schemaController: controllers.schemaController,
                                            dateParser: controllers.dateParser,
                                            backgroundUploader: backgroundUploader,
                                            syncDelayIntervals: DelayIntervals.sync,
                                            conflictDelays: DelayIntervals.conflict)
        let fileDownloader = FileDownloader(userId: userId, apiClient: controllers.apiClient, fileStorage: controllers.fileStorage)
        let webSocketController = WebSocketController()

        self.dbStorage = dbStorage
        self.syncScheduler = SyncScheduler(controller: syncController)
        self.changeObserver = RealmObjectChangeObserver(dbStorage: dbStorage)
        self.itemLocaleController = RItemLocaleController(schemaController: controllers.schemaController, dbStorage: dbStorage)
        self.backgroundUploader = backgroundUploader
        self.fileDownloader = fileDownloader
        self.webSocketController = webSocketController
        self.disposeBag = DisposeBag()

        let coordinator = try dbStorage.createCoordinator()
        try coordinator.perform(request: InitializeCustomLibrariesDbRequest())
    }

    /// Connects to websocket to monitor changes and performs initial sync.
    fileprivate func enableSync(apiKey: String) {
        self.itemLocaleController.loadLocale()

        // Observe sync to enable/disable the device falling asleep
        self.syncScheduler.syncController.progressObservable
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { progress in
                switch progress {
                case .aborted, .finished:
                    UIApplication.shared.isIdleTimerDisabled = false
                default:
                    UIApplication.shared.isIdleTimerDisabled = true
                }
            })
            .disposed(by: self.disposeBag)

        // Observe local changes to start sync
        self.changeObserver.observable
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] changedLibraries in
                self?.syncScheduler.request(syncType: .normal, for: changedLibraries)
            })
            .disposed(by: self.disposeBag)

        // Observe remote changes to start sync
        self.webSocketController.observable
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] libraryId in
                if let libraryId = libraryId {
                    self?.syncScheduler.request(syncType: .normal, for: [libraryId])
                } else {
                    self?.syncScheduler.request(syncType: .normal)
                }
            })
            .disposed(by: self.disposeBag)

        // Connect to websockets and start sync
        self.webSocketController.connect(apiKey: apiKey, completed: { [weak self] in
            self?.syncScheduler.request(syncType: .normal)
        })
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
        DDLogInfo("DB file path: \(file.createUrl().absoluteString)")
        return RealmDbStorage(config: Database.mainConfiguration(url: file.createUrl()))
    }
}
