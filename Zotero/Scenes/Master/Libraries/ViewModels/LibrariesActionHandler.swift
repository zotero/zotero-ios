//
//  LibrariesActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 27/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct LibrariesActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias State = LibrariesState
    typealias Action = LibrariesAction

    unowned let dbStorage: DbStorage
    let backgroundQueue: DispatchQueue

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.backgroundQueue = DispatchQueue(label: "org.zotero.LibrariesActionHandler.backgroundQueue", qos: .userInteractive)
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
            self.perform(request: DeleteGroupDbRequest(groupId: groupId)) { error in
                guard let error = error else { return }

                DDLogError("LibrariesActionHandler: can't delete group - \(error)")

                // TODO: - show error
            }
        }
    }

    private func loadData(in viewModel: ViewModel<LibrariesActionHandler>) {
        do {
            try self.dbStorage.perform(on: .main, with: { coordinator in
                let libraries = try coordinator.perform(request: ReadAllCustomLibrariesDbRequest())
                let groups = try coordinator.perform(request: ReadAllGroupsDbRequest())

                let groupsToken = groups.observe { [weak viewModel] changes in
                    guard let viewModel = viewModel else { return }
                    switch changes {
                    case .update(_, let deletions, _, _):
                        self.update(viewModel: viewModel) { state in
                            state.changes = .groups
                            if !deletions.isEmpty {
                                state.changes.insert(.groupDeletion)
                            }
                        }

                    case .initial: break
                    case .error: break
                    }
                }

                self.update(viewModel: viewModel) { state in
                    state.groupLibraries = groups
                    state.customLibraries = libraries
                    state.groupsToken = groupsToken
                }
            })
        } catch let error {
            DDLogError("LibrariesStore: can't load libraries - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .cantLoadData
            }
        }
    }
}
