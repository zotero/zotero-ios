//
//  AnnotationPageLabelActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 01.12.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AnnotationPageLabelActionHandler: ViewModelActionHandler {
    typealias Action = AnnotationPageLabelAction
    typealias State = AnnotationPageLabelState

    func process(action: AnnotationPageLabelAction, in viewModel: ViewModel<AnnotationPageLabelActionHandler>) {
        switch action {
        case .setLabel(let label):
            self.update(viewModel: viewModel) { state in
                state.label = label
            }

        case .setUpdateSubsequentLabels(let update):
            self.update(viewModel: viewModel) { state in
                state.updateSubsequentPages = update
            }
        }
    }
}
