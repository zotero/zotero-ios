//
//  CitationBibliographyExportActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 29.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CitationBibliographyExportActionHandler: ViewModelActionHandler {
    typealias State = CitationBibliographyExportState
    typealias Action = CitationBibliographyExportAction

    private unowned let citationController: CitationController

    init(citationController: CitationController) {
        self.citationController = citationController
    }

    func process(action: CitationBibliographyExportAction, in viewModel: ViewModel<CitationBibliographyExportActionHandler>) {
        switch action {
        case .setMethod(let method):
            self.update(viewModel: viewModel) { state in
                state.method = method
            }

        case .setMode(let mode):
            self.update(viewModel: viewModel) { state in
                state.mode = mode
            }

        case .setType(let type):
            self.update(viewModel: viewModel) { state in
                state.type = type
            }

        case .setStyle(let style):
            self.update(viewModel: viewModel) { state in
                state.style = style
                if !state.style.supportsBibliography {
                    state.mode = .citation
                }
            }

        case .setLocale(let id, let name):
            self.update(viewModel: viewModel) { state in
                state.localeId = id
                state.localeName = name
            }
        }
    }
}
