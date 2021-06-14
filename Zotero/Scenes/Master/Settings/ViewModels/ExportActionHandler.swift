//
//  ExportActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 11.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct ExportActionHandler: ViewModelActionHandler {
    typealias Action = ExportAction
    typealias State = ExportState

    func process(action: ExportAction, in viewModel: ViewModel<ExportActionHandler>) {
        switch action {
        case .setCopyAsHtml(let value):
            self.update(viewModel: viewModel) { state in
                state.copyAsHtml = value
            }
            Defaults.shared.exportCopyAsHtml = value

        case .updateLocale(let title):
            self.update(viewModel: viewModel) { state in
                state.selectedLanguage = title
            }

        case .updateStyle(let title):
            self.update(viewModel: viewModel) { state in
                state.selectedStyle = title
            }
        }
    }
}
