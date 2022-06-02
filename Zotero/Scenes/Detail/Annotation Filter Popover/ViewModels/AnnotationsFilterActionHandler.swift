//
//  AnnotationsFilterActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 01.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AnnotationsFilterActionHandler: ViewModelActionHandler {
    typealias Action = AnnotationsFilterAction
    typealias State = AnnotationsFilterState

    func process(action: AnnotationsFilterAction, in viewModel: ViewModel<AnnotationsFilterActionHandler>) {
        switch action {
        case .setTags(let tags):
            self.update(viewModel: viewModel) { state in
                state.tags = tags
                state.changes = .tags
            }

        case .toggleColor(let color):
            guard viewModel.state.availableColors.contains(color) else { return }
            self.update(viewModel: viewModel) { state in
                if state.colors.contains(color) {
                    state.colors.remove(color)
                } else {
                    state.colors.insert(color)
                }
                state.changes = .colors
            }

        case .clear:
            self.update(viewModel: viewModel) { state in
                state.tags = []
                state.colors = []
                state.changes = [.colors, .tags]
            }
        }
    }
}
