//
//  SettingsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

import CocoaLumberjack
import RxSwift

struct SettingsActionHandler: ViewModelActionHandler {
    typealias Action = SettingsAction
    typealias State = SettingsState

    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    private unowned let sessionController: SessionController
    private unowned let syncScheduler: SynchronizationScheduler
    private unowned let debugLogging: DebugLogging
    private unowned let translatorsController: TranslatorsController
    private let disposeBag: DisposeBag

    init(dbStorage: DbStorage, fileStorage: FileStorage, sessionController: SessionController,
         syncScheduler: SynchronizationScheduler, debugLogging: DebugLogging, translatorsController: TranslatorsController) {
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.sessionController = sessionController
        self.syncScheduler = syncScheduler
        self.debugLogging = debugLogging
        self.translatorsController = translatorsController
        self.disposeBag = DisposeBag()
    }

    func process(action: SettingsAction, in viewModel: ViewModel<SettingsActionHandler>) {
        switch action {
        case .setAskForSyncPermission(let value):
            Defaults.shared.askForSyncPermission = value
            self.update(viewModel: viewModel) { state in
                state.askForSyncPermission = value
            }

        case .setShowCollectionItemCounts(let value):
            Defaults.shared.showCollectionItemCount = value
            self.update(viewModel: viewModel) { state in
                state.showCollectionItemCount = value
            }

        case .startSync:
            self.syncScheduler.requestFullSync()

        case .cancelSync:
            self.syncScheduler.cancelSync()

        case .setLogoutAlertVisible(let visible):
            self.update(viewModel: viewModel) { state in
                state.logoutAlertVisible = visible
            }

        case .logout:
            self.update(viewModel: viewModel) { state in
                state.logoutAlertVisible = false
            }
            self.sessionController.reset()

        case .startObserving:
            self.observeTranslatorUpdate(in: viewModel)
            self.observeSyncChanges(in: viewModel)

        case .startImmediateLogging:
            self.debugLogging.start(type: .immediate)
            self.update(viewModel: viewModel) { state in
                state.isLogging = true
            }

        case .startLoggingOnNextLaunch:
            self.debugLogging.start(type: .nextLaunch)
            self.update(viewModel: viewModel) { state in
                state.isLogging = true
            }

        case .stopLogging:
            self.debugLogging.stop()
            self.update(viewModel: viewModel) { state in
                state.isLogging = false
            }

        case .updateTranslators:
            self.translatorsController.updateFromRepo()

        case .resetTranslators:
            self.translatorsController.resetToBundle()

        case .loadStorageData:
            self.loadStorageData(in: viewModel)

        case .deleteAllDownloads:
            self.removeAllDownloads(in: viewModel)

        case .deleteDownloadsInLibrary(let libraryId):
            self.removeDownloads(for: libraryId, in: viewModel)

        case .showDeleteAllQuestion(let show):
            self.update(viewModel: viewModel) { state in
                state.showDeleteAllQuestion = show
            }

        case .showDeleteLibraryQuestion(let library):
            self.update(viewModel: viewModel) { state in
                state.showDeleteLibraryQuestion = library
            }
        }
    }

    private func removeAllDownloads(in viewModel: ViewModel<SettingsActionHandler>) {
        do {
            try self.fileStorage.remove(Files.downloadDirectory)

            self.update(viewModel: viewModel) { state in
                for (key, _) in state.storageData {
                    state.storageData[key] = DirectoryData(fileCount: 0, totalSize: 0)
                }
                state.totalStorageData = DirectoryData(fileCount: 0, totalSize: 0)
                state.showDeleteAllQuestion = false
            }

            NotificationCenter.default.post(name: .attachmentFileDeleted, object: AttachmentFileDeletedNotification.all)
        } catch let error {
            DDLogError("SettingsActionHandler: can't remove download directory - \(error)")
            // TODO: - Show error to user
        }
    }

    private func removeDownloads(for libraryId: LibraryIdentifier, in viewModel: ViewModel<SettingsActionHandler>) {
        do {
            try self.fileStorage.remove(Files.libraryDirectory(for: libraryId))
            let newTotal = self.fileStorage.directoryData(for: Files.downloadDirectory)

            self.update(viewModel: viewModel) { state in
                state.storageData[libraryId] = DirectoryData(fileCount: 0, totalSize: 0)
                state.totalStorageData = newTotal
                state.showDeleteLibraryQuestion = nil
            }

            NotificationCenter.default.post(name: .attachmentFileDeleted, object: AttachmentFileDeletedNotification.library(libraryId))
        } catch let error {
            DDLogError("SettingsActionHandler: can't remove library downloads - \(error)")
            // TODO: - Show error to user
        }
    }

    private func loadStorageData(in viewModel: ViewModel<SettingsActionHandler>) {
        do {
            let coordinator = try self.dbStorage.createCoordinator()
            let libraries = Array((try coordinator.perform(request: ReadAllCustomLibrariesDbRequest())).map(Library.init)) +
                            (try coordinator.perform(request: ReadAllGroupsDbRequest())).map(Library.init)

            let (storageData, totalData) = self.storageData(for: libraries)

            self.update(viewModel: viewModel) { state in
                state.libraries = libraries
                state.storageData = storageData
                state.totalStorageData = totalData
            }
        } catch let error {
            DDLogError("SettingsActionHandler: can't load libraries - \(error)")
            // TODO: - Show error to user
        }
    }

    private func storageData(for libraries: [Library]) -> (libraryData: [LibraryIdentifier: DirectoryData], totalData: DirectoryData?) {
        var storageData: [LibraryIdentifier: DirectoryData] = [:]
        for library in libraries {
            if let data = self.fileStorage.directoryData(for: Files.libraryDirectory(for: library.identifier)) {
                storageData[library.identifier] = data
            }
        }
        let totalData = self.fileStorage.directoryData(for: Files.downloadDirectory)
        return (storageData, totalData)
    }

    private func observeTranslatorUpdate(in viewModel: ViewModel<SettingsActionHandler>) {
        self.translatorsController.isLoading
                                  .observeOn(MainScheduler.instance)
                                  .subscribe(onNext: { [weak viewModel] isLoading in
                                      guard let viewModel = viewModel else { return }
                                      self.update(viewModel: viewModel) { state in
                                          state.isUpdatingTranslators = isLoading
                                      }
                                  })
                                  .disposed(by: self.disposeBag)
    }

    private func observeSyncChanges(in viewModel: ViewModel<SettingsActionHandler>) {
        self.syncScheduler.syncController.progressObservable
                                         .observeOn(MainScheduler.instance)
                                         .subscribe(onNext: { [weak viewModel] progress in
                                             guard let viewModel = viewModel else { return }
                                             self.update(viewModel: viewModel) { state in
                                                switch progress {
                                                case .aborted, .finished:
                                                    state.isSyncing = false
                                                default:
                                                    state.isSyncing = true
                                                }
                                             }
                                         })
                                         .disposed(by: self.disposeBag)
    }
}
