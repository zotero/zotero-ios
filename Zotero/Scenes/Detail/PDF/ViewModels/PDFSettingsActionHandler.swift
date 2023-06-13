//
//  PDFSettingsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 02.03.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import PSPDFKit

struct PDFSettingsActionHandler: ViewModelActionHandler {
    typealias Action = PDFSettingsAction
    typealias State = PDFSettingsState

    func process(action: PDFSettingsAction, in viewModel: ViewModel<PDFSettingsActionHandler>) {
        switch action {
        case .setTransition(let pageTransition):
            self.update(viewModel: viewModel) { state in
                state.settings.transition = pageTransition
            }

        case .setPageMode(let pageMode):
            self.update(viewModel: viewModel) { state in
                state.settings.pageMode = pageMode
            }

        case .setDirection(let direction):
            self.update(viewModel: viewModel) { state in
                state.settings.direction = direction
            }

        case .setPageFitting(let fitting):
            self.update(viewModel: viewModel) { state in
                state.settings.pageFitting = fitting
            }

        case .setAppearanceMode(let appearanceMode):
            self.update(viewModel: viewModel) { state in
                state.settings.appearanceMode = appearanceMode
            }

        case .setIdleTimerDisabled(let disabled):
            self.update(viewModel: viewModel) { state in
                state.settings.idleTimerDisabled = disabled
            }
        }
    }
}
