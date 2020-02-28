//
//  SinglePickerActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct SinglePickerActionHandler: ViewModelActionHandler {
    typealias State = SinglePickerState
    typealias Action = SinglePickerAction

    func process(action: SinglePickerAction, in viewModel: ViewModel<SinglePickerActionHandler>) {
        switch action {
        case .select(let value):
            self.update(viewModel: viewModel) { state in
                state.selectedRow = value
            }
        }
    }
}
