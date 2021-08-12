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
            Defaults.shared.quickCopyAsHtml = value

        case .updateLocale(let locale):
            Defaults.shared.quickCopyLocaleId = locale.id
            self.update(viewModel: viewModel) { state in
                state.selectedLanguage = locale.name
            }

        case .updateStyle(let style):
            guard style.identifier != viewModel.state.selectedStyle else { return }
            Defaults.shared.quickCopyStyleId = style.identifier
            Defaults.shared.quickCopyParentStyleId = style.dependencyId ?? ""
            self.update(viewModel: viewModel) { state in
                state.selectedStyle = style.title
            }
        }
    }
}
