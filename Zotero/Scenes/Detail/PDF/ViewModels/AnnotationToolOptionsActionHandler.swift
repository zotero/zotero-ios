//
//  AnnotationToolOptionsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 20.01.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AnnotationToolOptionsActionHandler: ViewModelActionHandler {
    typealias Action = AnnotationToolOptionsAction
    typealias State = AnnotationToolOptionsState

    func process(action: AnnotationToolOptionsAction, in viewModel: ViewModel<AnnotationToolOptionsActionHandler>) {
        switch action {
        case .setSize(let size):
            self.update(viewModel: viewModel) { state in
                state.size = size
                state.changes = .size
            }

        case .setColorHex(let hex):
            self.update(viewModel: viewModel) { state in
                state.colorHex = hex
                state.changes = .color
            }
        }
    }
}
