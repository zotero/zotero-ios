//
//  AnnotationToolsSettingsViewModel.swift
//  Zotero
//
//  Created by Michal Rentka on 12.12.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import OrderedCollections

struct AnnotationToolsSettingsViewModel: ViewModelActionHandler {
    typealias Action = AnnotationToolsSettingsAction
    typealias State = AnnotationToolsSettingsState
    
    func process(action: AnnotationToolsSettingsAction, in viewModel: ViewModel<AnnotationToolsSettingsViewModel>) {
        switch action {
        case .move(let fromIndices, let toIndex, let section):
            update(viewModel: viewModel) { state in
                switch section {
                case .pdf:
                    state.pdfTools = move(fromIndices: fromIndices, toIndex: toIndex, inOrderedDictionary: state.pdfTools)
                    
                case .htmlEpub:
                    state.htmlEpubTools = move(fromIndices: fromIndices, toIndex: toIndex, inOrderedDictionary: state.htmlEpubTools)
                }
            }

        case .setVisible(let isVisible, let tool, let section):
            update(viewModel: viewModel) { state in
                switch section {
                case .pdf:
                    state.pdfTools[tool] = isVisible

                case .htmlEpub:
                    state.htmlEpubTools[tool] = isVisible
                }
            }

        case .save:
            Defaults.shared.pdfAnnotationTools = viewModel.state.pdfTools.keys.compactMap({ viewModel.state.pdfTools[$0] == true ? $0 : nil })
            Defaults.shared.htmlEpubAnnotationTools = viewModel.state.htmlEpubTools.keys.compactMap({ viewModel.state.htmlEpubTools[$0] == true ? $0 : nil })
        }
    }

    private func move(fromIndices: IndexSet, toIndex: Int, inOrderedDictionary orderedDictionary: OrderedDictionary<AnnotationTool, Bool>) -> OrderedDictionary<AnnotationTool, Bool> {
        var array = orderedDictionary.compactMap { key, value in (key, value) }
        array.move(fromOffsets: fromIndices, toOffset: toIndex)
        return OrderedDictionary(uniqueKeysWithValues: array)
    }
}
