//
//  LibrariesActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 27/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct LibrariesActionHandler: ViewModelActionHandler {
    typealias State = LibrariesState
    typealias Action = LibrariesAction

    private let dbStorage: DbStorage

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
    }

    func process(action: LibrariesAction, in viewModel: ViewModel<LibrariesActionHandler>) {
        switch action {
        case .loadData:
            self.loadData(in: viewModel)

        case .setCustomLibraries(let results):
            self.update(viewModel: viewModel) { state in
                state.customLibraries = results
            }

        case .setGroupLibraries(let results):
            self.update(viewModel: viewModel) { state in
                state.groupLibraries = results
            }

        case .showDeleteGroupQuestion(let question):
            self.update(viewModel: viewModel) { state in
                state.deleteGroupQuestion = question
            }

        case .deleteGroup(let groupId):
            DispatchQueue.global(qos: .userInitiated).async {
                self.deleteGroup(id: groupId, dbStorage: self.dbStorage)
            }
        }
    }

    private func loadData(in viewModel: ViewModel<LibrariesActionHandler>) {
        do {
            let libraries = try self.dbStorage.createCoordinator().perform(request: ReadAllCustomLibrariesDbRequest())
            let groups = try self.dbStorage.createCoordinator().perform(request: ReadAllGroupsDbRequest())

            let librariesToken = libraries.observe({ [weak viewModel] changes in
                guard let viewModel = viewModel else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    self.update(viewModel: viewModel) { state in
                        state.customLibraries = objects
                    }
                case .initial: break
                case .error: break
                }
            })

            let groupsToken = groups.observe { [weak viewModel] changes in
                guard let viewModel = viewModel else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    self.update(viewModel: viewModel) { state in
                        state.groupLibraries = objects
                    }
                case .initial: break
                case .error: break
                }
            }

            self.update(viewModel: viewModel) { state in
                state.groupLibraries = groups
                state.customLibraries = libraries
                state.groupsToken = groupsToken
                state.librariesToken = librariesToken
            }
        } catch let error {
            DDLogError("LibrariesStore: can't load libraries - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .cantLoadData
            }
        }
    }

    private func deleteGroup(id: Int, dbStorage: DbStorage) {
        do {
            try dbStorage.createCoordinator().perform(request: DeleteGroupDbRequest(groupId: id))
        } catch let error {
            DDLogError("LibrariesActionHandler: can't delete group - \(error)")
        }
    }
}
