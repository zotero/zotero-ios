//
//  HtmlEpubReaderActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 14.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

final class HtmlEpubReaderActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias Action = HtmlEpubReaderAction
    typealias State = HtmlEpubReaderState

    unowned let dbStorage: DbStorage
    unowned let schemaController: SchemaController
    let backgroundQueue: DispatchQueue

    init(dbStorage: DbStorage, schemaController: SchemaController) {
        self.dbStorage = dbStorage
        self.schemaController = schemaController
        self.backgroundQueue = DispatchQueue(label: "org.zotero.Zotero.HtmlEpubReaderActionHandler.queue", qos: .userInteractive)
    }

    func process(action: HtmlEpubReaderAction, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        switch action {
        case .toggleTool(let tool):
            toggle(tool: tool, in: viewModel)

        case .loadDocument:
            load(in: viewModel)

        case .saveAnnotations(let params):
            saveAnnotations(params: params, in: viewModel)

        case .selectAnnotations(let params):
            selectAnnotations(params: params, in: viewModel)
        }
    }

    private func selectAnnotations(params: [String: Any], in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
    }

    private func saveAnnotations(params: [String: Any], in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        guard let rawAnnotations = params["annotations"] as? [[String: Any]], !rawAnnotations.isEmpty else {
            DDLogError("HtmlEpubReaderActionHandler: annotations missing or empty - \(params["annotations"] ?? [])")
            return
        }

        let annotations = parse(annotations: rawAnnotations)

        guard annotations.isEmpty else {
            DDLogError("HtmlEpubReaderActionHandler: could not parse annotations")
            return
        }

        let request = CreateHtmlEpubAnnotationsDbRequest(
            attachmentKey: viewModel.state.key,
            libraryId: viewModel.state.library.identifier,
            annotations: annotations,
            userId: viewModel.state.userId,
            schemaController: schemaController
        )
        self.perform(request: request) { [weak viewModel] error in
            guard let error, let viewModel else { return }

            DDLogError("HtmlEpubReaderActionHandler: could not store annotations - \(error)")

            self.update(viewModel: viewModel) { state in
                state.error = .cantAddAnnotations
            }
        }

        func parse(annotations: [[String: Any]]) -> [HtmlEpubAnnotation] {
            return []
        }
    }

    private func load(in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        do {
            let data = try Data(contentsOf: viewModel.state.url)
            let jsArrayData = try JSONSerialization.data(withJSONObject: [UInt8](data))
            guard let jsArrayString = String(data: jsArrayData, encoding: .utf8) else {
                DDLogError("HtmlEpubReaderActionHandler: can't convert data to string")
                return
            }

            let documentData = HtmlEpubReaderState.DocumentData(buffer: jsArrayString, annotationsJson: "[]")
            self.update(viewModel: viewModel) { state in
                state.documentData = documentData
            }
        } catch let error {
            DDLogError("HtmlEpubReaderActionHandler: could not load document - \(error)")
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
