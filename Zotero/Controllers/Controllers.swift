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
    let noteConverter: NoteConverter

    var userControllers: UserControllers?
    private var sessionCancellable: AnyCancellable?

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["Zotero-API-Version": ApiConstants.version.description]
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
        apiClient.set(authToken: sessionController.sessionData?.apiToken)
        let schemaController = SchemaController()
        let translatorsController = TranslatorsController(apiClient: apiClient,
                                                          indexStorage: RealmDbStorage(config: TranslatorDatabase.configuration),
                                                          fileStorage: fileStorage)
        let fileCleanupController = AttachmentFileCleanupController(fileStorage: fileStorage)

        self.sessionController = sessionController
        self.apiClient = apiClient
        self.secureStorage = secureStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.dragDropController = DragDropController()
        self.crashReporter = crashReporter
        self.debugLogging = debugLogging
        self.translatorsController = translatorsController
        self.annotationPreviewController = AnnotationPreviewController(previewSize: AnnotationsConfig.previewSize, fileStorage: fileStorage)
        self.urlDetector = UrlDetector()
        self.dateParser = DateParser()
        self.fileCleanupController = fileCleanupController
        self.pageController = PdfPageController()
        self.noteConverter = NoteConverter()

        if let userId = sessionController.sessionData?.userId {
            self.userControllers = UserControllers(userId: userId, controllers: self)
        }

        self.sessionCancellable = sessionController.$sessionData
                                                   .receive(on: DispatchQueue.main)
                                                   .dropFirst()
                                                   .sink { [weak self] data in
                                                       self?.update(sessionData: data)
                                                   }
    }

    func willEnterForeground() {
        self.crashReporter.processPendingReports()
        self.translatorsController.update()
        self.userControllers?.itemLocaleController.loadLocale()
        self.userControllers?.syncScheduler.requestFullSync()
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

    private func update(sessionData: SessionData?) {
        self.apiClient.set(authToken: sessionData?.apiToken)

        // Cleanup user controllers on logout
        self.userControllers?.cleanup()
        self.userControllers = sessionData.flatMap { UserControllers(userId: $0.userId, controllers: self) }
        // Enqueue full sync after successful login (
        self.userControllers?.syncScheduler.requestFullSync()
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

    init(userId: Int, controllers: Controllers) {
        let dbStorage = UserControllers.createDbStorage(for: userId, controllers: controllers)
        let backgroundUploadProcessor = BackgroundUploadProcessor(apiClient: controllers.apiClient,
                                                                  dbStorage: dbStorage,
                                                                  fileStorage: controllers.fileStorage)
        let backgroundUploader = BackgroundUploader(uploadProcessor: backgroundUploadProcessor)

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

        do {
            let coordinator = try dbStorage.createCoordinator()
            try coordinator.perform(request: InitializeCustomLibrariesDbRequest())
        } catch let error {
            // TODO: - handle the error a bit more graciously
            fatalError("UserControllers: can't create custom user library - \(error)")
        }
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
                               self?.syncScheduler.requestSync(for: changedLibraries)
                           })
                           .disposed(by: self.disposeBag)
    }

    func stopObserving() {
        self.disposeBag = DisposeBag()
    }

    private class func createDbStorage(for userId: Int, controllers: Controllers) -> DbStorage {
        do {
            let file = Files.dbFile(for: userId)
            try controllers.fileStorage.createDirectories(for: file)

            DDLogInfo("DB file path: \(file.createUrl().absoluteString)")

            return RealmDbStorage(config: MainDatabase.configuration(url: file.createUrl()))
        } catch let error {
            // TODO: - handle the error a bit more graciously
            fatalError("UserControllers: can't create DB file - \(error)")
        }
    }
}
