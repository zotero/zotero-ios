//
//  AnnotationEditActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 30.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import Foundation

struct AnnotationEditActionHandler: ViewModelActionHandler {
    typealias Action = AnnotationEditAction
    typealias State = AnnotationEditState

    func process(action: AnnotationEditAction, in viewModel: ViewModel<AnnotationEditActionHandler>) {
        switch action {
        case .setColor(let hexString):
            self.update(viewModel: viewModel) { state in
                state.color = hexString
                state.changes = .color
            }

        case .setLineWidth(let width):
            self.update(viewModel: viewModel) { state in
                state.lineWidth = width
            }
            
        case .setPageLabel(let label, let updateSubsequentPages):
            self.update(viewModel: viewModel) { state in
                state.pageLabel = label
                state.updateSubsequentLabels = updateSubsequentPages
                state.changes = .pageLabel
            }

        case .setHighlight(let text):
            self.update(viewModel: viewModel) { state in
                state.highlightText = text
            }
        }
    }
}

#endif
