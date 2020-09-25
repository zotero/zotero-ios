//
//  TagPickerActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 09/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

import CocoaLumberjack

struct TagPickerActionHandler: ViewModelActionHandler {
    typealias Action = TagPickerAction
    typealias State = TagPickerState

    private unowned let dbStorage: DbStorage

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
    }

    func process(action: TagPickerAction, in viewModel: ViewModel<TagPickerActionHandler>) {
        switch action {
        case .setSelected(let selected):
            self.update(viewModel: viewModel) { state in
                state.selectedTags = selected
            }

        case .load:
            self.load(in: viewModel)

        case .search(let term):
            self.search(with: term, in: viewModel)
        }
    }

    private func search(with term: String, in viewModel: ViewModel<TagPickerActionHandler>) {
        if !term.isEmpty {
            self.update(viewModel: viewModel) { state in
                if state.snapshot == nil {
                    state.snapshot = state.tags
                }
                state.searchTerm = term
                state.tags = (state.snapshot ?? state.tags).filter({ $0.name.lowercased().contains(term.lowercased()) })
            }
        } else {
            guard let snapshot = viewModel.state.snapshot else { return }
            self.update(viewModel: viewModel) { state in
                state.tags = snapshot
                state.snapshot = nil
                state.searchTerm = ""
            }
        }
    }

    private func load(in viewModel: ViewModel<TagPickerActionHandler>) {
        do {
            let request = ReadTagsDbRequest(libraryId: viewModel.state.libraryId)
            let tags = try self.dbStorage.createCoordinator().perform(request: request)
            self.update(viewModel: viewModel) { state in
                state.tags = tags
            }
        } catch let error {
            DDLogError("TagPickerStore: can't load tag: \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .loadingFailed
            }
        }
    }
}
