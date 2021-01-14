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
    let pageController: PdfPageController
    let htmlAttributedStringConverter: HtmlAttributedStringConverter
    let userInitialized: PassthroughSubject<Result<Bool, Error>, Never>

    var userControllers: UserControllers?
    // Stores initial error when initializing `UserControllers`. It's needed in case the error happens on app launch.
    // The event sent through `userInitialized` publisher is not received by scene, because this happens in AppDelegate `didFinishLaunchingWithOptions`.
    var userControllerError: Error?
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
        let sessionController = SessionController(secureStorage: secureStorage)
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
        self.pageController = PdfPageController()
        self.htmlAttributedStringConverter = HtmlAttributedStringConverter()
        self.userInitialized = PassthroughSubject()

        self.startObservingSession()
        self.update(with: self.sessionController.sessionData)
    }

    func willEnterForeground() {
        self.crashReporter.processPendingReports()
        self.translatorsController.update()
        self.userControllers?.itemLocaleController.loadLocale()
        self.userControllers?.syncScheduler.request(syncType: .normal)
        self.userControllers?.startObserving()
    }

    func didEnterBackground() {
        self.pageController.save()
        self.userControllers?.itemLocaleController.storeLocale()
        self.userControllers?.syncScheduler.cancelSync()
        self.userControllers?.stopObserving()
    }
    
    func willTerminate() {
        self.pageController.save()
    }

    private func startObservingSession() {
        self.sessionCancellable = self.sessionController.$sessionData
                                                        .receive(on: DispatchQueue.main)
                                                        .dropFirst()
                                                        .sink { [weak self] data in
                                                            self?.update(with: data)
                                                        }
    }

    private func update(with data: SessionData?) {
        // Cleanup user controllers on logout
        self.userControllers?.cleanup()

        if let data = data {
            self.initializeSession(with: data)
        } else {
            self.clearSession()
        }
    }

    private func initializeSession(with data: SessionData) {
        do {
            let controllers = try UserControllers(userId: data.userId, controllers: self)
            controllers.syncScheduler.request(syncType: .normal)
            self.userControllers = controllers

            self.apiClient.set(authToken: data.apiToken)

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
        self.apiClient.set(authToken: nil)
        self.userControllers = nil
        self.userControllerError = nil
        self.userInitialized.send(.success(false))
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

    private static let schemaVersion: UInt64 = 9

    private var disposeBag: DisposeBag

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

        self.dbStorage = dbStorage
        self.syncScheduler = SyncScheduler(controller: syncController)
        self.changeObserver = RealmObjectChangeObserver(dbStorage: dbStorage)
        self.itemLocaleController = RItemLocaleController(schemaController: controllers.schemaController, dbStorage: dbStorage)
        self.backgroundUploader = backgroundUploader
        self.fileDownloader = fileDownloader
        self.disposeBag = DisposeBag()

        let coordinator = try dbStorage.createCoordinator()
        try coordinator.perform(request: InitializeCustomLibrariesDbRequest())
    }

    /// Called when user logs out and we need to cleanup stored/cached data
    func cleanup() {
        // Stop ongoing sync
        self.syncScheduler.cancelSync()
        // Clear DB storage
        self.dbStorage.clear()
        // Cancel all pending background uploads
        self.backgroundUploader.cancel()
        // TODO: - remove cached files
    }

    func startObserving() {
        self.syncScheduler
            .syncController
            .progressObservable.observeOn(MainScheduler.instance)
            .subscribe(onNext: { progress in
                switch progress {
                case .aborted, .finished:
                    UIApplication.shared.isIdleTimerDisabled = false
                default:
                    UIApplication.shared.isIdleTimerDisabled = true
                }
            })
            .disposed(by: self.disposeBag)

        self.changeObserver.observable
                           .observeOn(MainScheduler.instance)
                           .subscribe(onNext: { [weak self] changedLibraries in
                               self?.syncScheduler.request(syncType: .normal, for: changedLibraries)
                           })
                           .disposed(by: self.disposeBag)
    }

    func stopObserving() {
        self.disposeBag = DisposeBag()
    }

    private class func createDbStorage(for userId: Int, controllers: Controllers) throws -> DbStorage {
        let file = Files.dbFile(for: userId)
        try controllers.fileStorage.createDirectories(for: file)
        DDLogInfo("DB file path: \(file.createUrl().absoluteString)")
        return RealmDbStorage(config: Database.mainConfiguration(url: file.createUrl()))
    }
}
