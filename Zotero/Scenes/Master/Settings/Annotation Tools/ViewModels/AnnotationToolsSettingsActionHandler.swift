//
//  AnnotationToolsSettingsViewModel.swift
//  Zotero
//
//  Created by Michal Rentka on 12.12.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AnnotationToolsSettingsViewModel: ViewModelActionHandler {
    typealias Action = AnnotationToolsSettingsAction
    typealias State = AnnotationToolsSettingsState
    
    func process(action: AnnotationToolsSettingsAction, in viewModel: ViewModel<AnnotationToolsSettingsViewModel>) {
        switch action {
        case .move(let fromIndices, let toIndex, let section):
            update(viewModel: viewModel) { state in
                switch section {
                case .pdf:
                    state.pdfTools.move(fromOffsets: fromIndices, toOffset: toIndex)
                    
                case .htmlEpub:
                    state.htmlEpubTools.move(fromOffsets: fromIndices, toOffset: toIndex)
                }
            }
            
        case .reset(let section):
            update(viewModel: viewModel) { state in
                switch section {
                case .pdf:
                    state.pdfTools = [
                        AnnotationToolButton(type: .highlight, isVisible: true),
                        AnnotationToolButton(type: .underline, isVisible: true),
                        AnnotationToolButton(type: .note, isVisible: true),
                        AnnotationToolButton(type: .freeText, isVisible: true),
                        AnnotationToolButton(type: .image, isVisible: true),
                        AnnotationToolButton(type: .ink, isVisible: true),
                        AnnotationToolButton(type: .eraser, isVisible: true)
                    ]
                    
                case .htmlEpub:
                    state.htmlEpubTools = [
                        AnnotationToolButton(type: .highlight, isVisible: true),
                        AnnotationToolButton(type: .underline, isVisible: true),
                        AnnotationToolButton(type: .note, isVisible: true)
                    ]
                }
            }

        case .setVisible(let isVisible, let tool, let section):
            update(viewModel: viewModel) { state in
                switch section {
                case .pdf:
                    guard let index = state.pdfTools.firstIndex(where: { $0.type == tool }) else { return }
                    state.pdfTools[index] = AnnotationToolButton(type: tool, isVisible: isVisible)

                case .htmlEpub:
                    guard let index = state.htmlEpubTools.firstIndex(where: { $0.type == tool }) else { return }
                    state.htmlEpubTools[index] = AnnotationToolButton(type: tool, isVisible: isVisible)
                }
            }

        case .save:
            Defaults.shared.pdfAnnotationTools = viewModel.state.pdfTools
            Defaults.shared.htmlEpubAnnotationTools = viewModel.state.htmlEpubTools
        }
    }
}
