//
//  NoteEditorActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 07.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct NoteEditorActionHandler: ViewModelActionHandler {
    typealias Action = NoteEditorAction
    typealias State = NoteEditorState

    let saveAction: (String, [Tag]) -> Void

    func process(action: Action, in viewModel: ViewModel<NoteEditorActionHandler>) {
        switch action {
        case .save:
            self.saveAction(viewModel.state.text, viewModel.state.tags)

        case .setText(let text):
            self.update(viewModel: viewModel) { state in
                state.text = text
                state.changes = .save
            }

        case .setTags(let tags):
            self.update(viewModel: viewModel) { state in
                state.tags = tags
                state.changes = [.tags, .save]
            }
        }
    }
}
