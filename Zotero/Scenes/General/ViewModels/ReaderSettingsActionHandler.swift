//
//  ReaderSettingsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 02.03.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import PSPDFKit

struct ReaderSettingsActionHandler: ViewModelActionHandler {
    typealias Action = ReaderSettingsAction
    typealias State = ReaderSettingsState

    func process(action: ReaderSettingsAction, in viewModel: ViewModel<ReaderSettingsActionHandler>) {
        switch action {
        case .setTransition(let pageTransition):
            update(viewModel: viewModel) { state in
                state.transition = pageTransition
            }

        case .setPageMode(let pageMode):
            update(viewModel: viewModel) { state in
                state.pageMode = pageMode
            }

        case .setDirection(let direction):
            update(viewModel: viewModel) { state in
                state.scrollDirection = direction
            }

        case .setPageFitting(let fitting):
            update(viewModel: viewModel) { state in
                state.pageFitting = fitting
            }

        case .setAppearance(let appearance):
            update(viewModel: viewModel) { state in
                state.appearance = appearance
            }

        case .setPageSpreads(let isFirstPageAlwaysSingle):
            update(viewModel: viewModel) { state in
                state.isFirstPageAlwaysSingle = isFirstPageAlwaysSingle
            }
        }
    }
}
