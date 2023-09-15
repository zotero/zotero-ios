//
//  HtmlEpubReaderActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 14.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

final class HtmlEpubReaderActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias Action = HtmlEpubReaderAction
    typealias State = HtmlEpubReaderState

    unowned let dbStorage: DbStorage
    let backgroundQueue: DispatchQueue

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.backgroundQueue = DispatchQueue(label: "org.zotero.Zotero.HtmlEpubReaderActionHandler.queue", qos: .userInteractive)
    }

    func process(action: HtmlEpubReaderAction, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        switch action {
        case .toggleTool(let tool):
            self.toggle(tool: tool, in: viewModel)
        }
    }

    private func toggle(tool: AnnotationTool, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        self.update(viewModel: viewModel) { state in
            if state.activeTool == tool {
                state.activeTool = nil
            } else {
                state.activeTool = tool
            }
            state.changes = .activeTool
        }
    }
}
