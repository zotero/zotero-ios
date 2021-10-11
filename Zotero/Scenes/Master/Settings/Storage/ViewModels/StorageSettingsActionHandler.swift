//
//  StorageSettingsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 11.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct StorageSettingsActionHandler: ViewModelActionHandler {
    typealias Action = StorageSettingsAction
    typealias State = StorageSettingsState

    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    private unowned let fileCleanupController: AttachmentFileCleanupController

    init(dbStorage: DbStorage, fileStorage: FileStorage, fileCleanupController: AttachmentFileCleanupController) {
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.fileCleanupController = fileCleanupController
    }

    func process(action: StorageSettingsAction, in viewModel: ViewModel<StorageSettingsActionHandler>) {
        switch action {
        case .loadData:
            self.loadStorageData(in: viewModel)

        case .deleteAll:
            self.removeAllDownloads(in: viewModel)

        case .deleteInLibrary(let libraryId):
            self.removeDownloads(for: libraryId, in: viewModel)
        }
    }

    private func loadStorageData(in viewModel: ViewModel<StorageSettingsActionHandler>) {
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

    private func storageData(for libraries: [Library]) -> (libraryData: [LibraryIdentifier: DirectoryData], totalData: DirectoryData) {
        var storageData: [LibraryIdentifier: DirectoryData] = [:]
        for library in libraries {
            let libraryId = library.identifier
            let data = self.fileStorage.directoryData(for: [Files.downloads(for: libraryId), Files.annotationPreviews(for: libraryId)])
            storageData[library.identifier] = data
        }
        let totalData = self.fileStorage.directoryData(for: [Files.downloads, Files.annotationPreviews])
        return (storageData, totalData)
    }

    private func removeAllDownloads(in viewModel: ViewModel<StorageSettingsActionHandler>) {
        self.fileCleanupController.delete(.all) { [weak viewModel] deleted in
            guard deleted, let viewModel = viewModel else { return }
            self.update(viewModel: viewModel) { state in
                for (key, _) in state.storageData {
                    state.storageData[key] = DirectoryData(fileCount: 0, mbSize: 0)
                }
                state.totalStorageData = DirectoryData(fileCount: 0, mbSize: 0)
            }
        }
    }

    private func removeDownloads(for libraryId: LibraryIdentifier, in viewModel: ViewModel<StorageSettingsActionHandler>) {
        self.fileCleanupController.delete(.library(libraryId)) { [weak viewModel] deleted in
            guard deleted, let viewModel = viewModel else { return }

            let newTotal = self.fileStorage.directoryData(for: [Files.downloads, Files.annotationPreviews])

            self.update(viewModel: viewModel) { state in
                state.storageData[libraryId] = DirectoryData(fileCount: 0, mbSize: 0)
                state.totalStorageData = newTotal
            }
        }
    }
}
