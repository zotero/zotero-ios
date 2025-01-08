//
//  AnnotationPopoverActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 25.10.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AnnotationPopoverActionHandler: ViewModelActionHandler {
    typealias Action = AnnotationPopoverAction
    typealias State = AnnotationPopoverState

    func process(action: AnnotationPopoverAction, in viewModel: ViewModel<AnnotationPopoverActionHandler>) {
        switch action {
        case .setColor(let hexString):
            update(viewModel: viewModel) { state in
                state.color = hexString
                state.changes = .color
            }

        case .setLineWidth(let width):
            update(viewModel: viewModel) { state in
                state.lineWidth = width
                state.changes = .lineWidth
            }

        case .setPageLabel(let label, let updateSubsequentPages):
            update(viewModel: viewModel) { state in
                state.pageLabel = label
                state.updateSubsequentLabels = updateSubsequentPages
                state.changes = .pageLabel
            }

        case .setComment(let comment):
            update(viewModel: viewModel) { state in
                state.comment = comment
                state.changes = .comment
            }

        case .setTags(let tags):
            update(viewModel: viewModel) { state in
                state.tags = tags
                state.changes = .tags
            }

        case .delete:
            update(viewModel: viewModel) { state in
                state.changes = .deletion
            }

        case .setProperties(let type, let pageLabel, let updateSubsequentLabels, let highlightText):
            update(viewModel: viewModel) { state in
                if state.type != type {
                    state.type = type
                    state.changes.insert(.type)
                }

                if state.pageLabel != pageLabel {
                    state.pageLabel = pageLabel
                    state.updateSubsequentLabels = updateSubsequentLabels
                    state.changes.insert(.pageLabel)
                }

                if state.highlightText != highlightText {
                    state.highlightText = highlightText
                    state.changes.insert(.highlight)
                }
            }
        }
    }
}
