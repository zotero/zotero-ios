//
//  Controllers.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RxSwift

/// Global controllers which don't need user session
class Controllers {
    let apiClient: ApiClient
    let secureStorage: SecureStorage
    let dbStorage: DbStorage
    let fileStorage: FileStorage
    let itemFieldsController: ItemFieldsController

    var userControllers: UserControllers?

    init() {
        let itemFieldsController = ItemFieldsController()
        let fileStorage = FileStorageController()
        let secureStorage = KeychainSecureStorage()
        let authToken = ApiConstants.authToken ?? secureStorage.apiToken
        let apiClient = ZoteroApiClient(baseUrl: ApiConstants.baseUrlString,
                                        headers: ["Zotero-API-Version": ApiConstants.version.description])
        apiClient.set(authToken: authToken)

        do {
            let file = Files.dbFile
            DDLogInfo("DB file path: \(file.createUrl().absoluteString)")
            try fileStorage.createDictionaries(for: file)
            let dbStorage = RealmDbStorage(url: file.createUrl())
            try dbStorage.createCoordinator().perform(request: InitializeMyLibraryDbRequest())
            self.dbStorage = dbStorage
        } catch let error {
            fatalError("Controllers: Could not initialize My Library - \(error.localizedDescription)")
        }

        self.apiClient = apiClient
        self.secureStorage = secureStorage
        self.fileStorage = fileStorage
        self.itemFieldsController = itemFieldsController

        // Not logged in, don't setup user controllers
        if authToken == nil { return }

        do {
            let userId: Int
            if let id = ApiConstants.userId {
                userId = id
            } else {
                userId = try dbStorage.createCoordinator().perform(request: ReadUserDbRequest()).identifier
            }
            self.userControllers = UserControllers(userId: userId, controllers: self)
        } catch let error {
            DDLogError("Controllers: User logged in, but could not load userId - \(error.localizedDescription)")
            secureStorage.apiToken = nil
        }
    }

    func sessionChanged(userId: Int?) {
        self.userControllers = userId.flatMap({ UserControllers(userId: $0, controllers: self) })
    }
}

/// Global controllers for logged in user
class UserControllers {
    let syncScheduler: SynchronizationScheduler
    let changeObserver: ObjectChangeObserver
    private let disposeBag: DisposeBag

    init(userId: Int, controllers: Controllers) {
        self.disposeBag = DisposeBag()
        let syncHandler = SyncActionHandlerController(userId: userId, apiClient: controllers.apiClient,
                                                      dbStorage: controllers.dbStorage,
                                                      fileStorage: controllers.fileStorage)
        let updateDataSource = UpdateDataSource(dbStorage: controllers.dbStorage)
        let syncController = SyncController(userId: userId, handler: syncHandler, updateDataSource: updateDataSource)
        self.syncScheduler = SyncScheduler(controller: syncController)
        self.changeObserver = RealmObjectChangeObserver(dbStorage: controllers.dbStorage)

        self.performInitialActions()
    }

    private func performInitialActions() {
        self.syncScheduler.requestFullSync()
        self.changeObserver.observable
                           .observeOn(MainScheduler.instance)
                           .subscribe(onNext: { [weak self] changedLibraries in
                               self?.syncScheduler.requestSync(for: changedLibraries)
                           })
                           .disposed(by: self.disposeBag)
    }
}
