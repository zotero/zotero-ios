//
//  CreatorEditActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 28/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CreatorEditActionHandler: ViewModelActionHandler {
    typealias State = CreatorEditState
    typealias Action = CreatorEditAction

    private unowned let schemaController: SchemaController

    init(schemaController: SchemaController) {
        self.schemaController = schemaController
    }

    func process(action: CreatorEditAction, in viewModel: ViewModel<CreatorEditActionHandler>) {
        self.update(viewModel: viewModel) { state in
            switch action {
            case .setType(let type):
                state.creator.type = type
                state.creator.localizedType = schemaController.localized(creator: type) ?? ""
                state.creator.primary = schemaController.creatorIsPrimary(type, itemType: viewModel.state.itemType)
                state.changes = .type

            case .setNamePresentation(let namePresentation):
                state.creator.namePresentation = namePresentation
                state.changes = [.name, .namePresentation]
                Defaults.shared.creatorNamePresentation = namePresentation

            case .setFullName(let name):
                state.creator.fullName = name
                state.changes = .name

            case .setFirstName(let name):
                state.creator.firstName = name
                state.changes = .name

            case .setLastName(let name):
                state.creator.lastName = name
                state.changes = .name
            }
        }
    }
}
