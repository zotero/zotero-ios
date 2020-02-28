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
