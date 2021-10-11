//
//  SavingSettingsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 11.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct SavingSettingsActionHandler: ViewModelActionHandler {
    typealias Action = SavingSettingsAction
    typealias State = SavingSettingsState

    func process(action: SavingSettingsAction, in viewModel: ViewModel<SavingSettingsActionHandler>) {
        switch action {
        case .setIncludeTags(let value):
            self.update(viewModel: viewModel) { state in
                state.includeTags = value
            }

        case .setIncludeAttachment(let value):
            self.update(viewModel: viewModel) { state in
                state.includeAttachment = value
            }
        }
    }
}
