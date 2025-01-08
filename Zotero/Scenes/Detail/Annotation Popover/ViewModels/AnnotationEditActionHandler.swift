//
//  AnnotationEditActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 30.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AnnotationEditActionHandler: ViewModelActionHandler {
    typealias Action = AnnotationEditAction
    typealias State = AnnotationEditState

    func process(action: AnnotationEditAction, in viewModel: ViewModel<AnnotationEditActionHandler>) {
        switch action {
        case .setColor(let hexString):
            update(viewModel: viewModel) { state in
                state.color = hexString
                state.changes = .color
            }

        case .setLineWidth(let width):
            update(viewModel: viewModel) { state in
                state.lineWidth = width
            }
            
        case .setPageLabel(let label, let updateSubsequentPages):
            update(viewModel: viewModel) { state in
                state.pageLabel = label
                state.updateSubsequentLabels = updateSubsequentPages
                state.changes = .pageLabel
            }

        case .setHighlight(let text):
            update(viewModel: viewModel) { state in
                state.highlightText = text
            }

        case .setFontSize(let size):
            update(viewModel: viewModel) { state in
                state.fontSize = size
            }

        case .convertBetweenHighlightAndUnderline:
            update(viewModel: viewModel) { state in
                switch state.type {
                case .highlight:
                    state.type = .underline
                    state.changes = .type

                case .underline:
                    state.type = .highlight
                    state.changes = .type

                case .freeText, .image, .ink, .note:
                    break
                }
            }
        }
    }
}
