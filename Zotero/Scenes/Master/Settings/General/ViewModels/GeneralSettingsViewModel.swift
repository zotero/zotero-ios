//
//  GeneralSettingsViewModel.swift
//  Zotero
//
//  Created by Michal Rentka on 11.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation


struct GeneralSettingsActionHandler: ViewModelActionHandler {
    typealias Action = GeneralSettingsAction
    typealias State = GeneralSettingsState

    func process(action: GeneralSettingsAction, in viewModel: ViewModel<GeneralSettingsActionHandler>) {
        switch action {
        case .setShowSubcollectionItems(let value):
            self.update(viewModel: viewModel) { state in
                state.showSubcollectionItems = value
            }

        case .setShowCollectionItemCounts(let value):
            self.update(viewModel: viewModel) { state in
                state.showCollectionItemCounts = value
            }
        }
    }
}
