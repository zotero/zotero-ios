//
//  CitationBibliographyExportActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 29.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

import CocoaLumberjackSwift
import RxSwift

struct CitationBibliographyExportActionHandler: ViewModelActionHandler {
    typealias State = CitationBibliographyExportState
    typealias Action = CitationBibliographyExportAction

    private unowned let citationController: CitationController
    private unowned let fileStorage: FileStorage
    private unowned let webView: WKWebView
    private let queue: DispatchQueue
    private let disposeBag: DisposeBag

    init(citationController: CitationController, fileStorage: FileStorage, webView: WKWebView) {
        self.citationController = citationController
        self.fileStorage = fileStorage
        self.webView = webView
        self.queue = DispatchQueue(label: "org.zotero.CitationBibliographyExportActionHandler", qos: .userInteractive)
        self.disposeBag = DisposeBag()
    }

    func process(action: CitationBibliographyExportAction, in viewModel: ViewModel<CitationBibliographyExportActionHandler>) {
        switch action {
        case .setMethod(let method):
            self.update(viewModel: viewModel) { state in
                state.method = method
                Defaults.shared.exportOutputMethod = method
            }

        case .setMode(let mode):
            self.update(viewModel: viewModel) { state in
                state.mode = mode
                Defaults.shared.exportOutputMode = mode
            }

        case .setType(let type):
            self.update(viewModel: viewModel) { state in
                state.type = type
            }

        case .setStyle(let style):
            self.update(viewModel: viewModel) { state in
                state.style = style
                Defaults.shared.exportStyleId = style.identifier

                if !state.style.supportsBibliography {
                    state.mode = .citation
                }

                if let localeId = state.style.defaultLocale {
                    state.localeId = localeId
                    state.localeName = Locale.current.localizedString(forIdentifier: localeId) ?? localeId
                    state.languagePickerEnabled = false
                } else {
                    state.localeId = Defaults.shared.exportLocaleId
                    state.localeName = Locale.current.localizedString(forIdentifier: Defaults.shared.exportLocaleId) ?? Defaults.shared.exportLocaleId
                    state.languagePickerEnabled = true
                }
            }

        case .setLocale(let id, let name):
            self.update(viewModel: viewModel) { state in
                state.localeId = id
                state.localeName = name
                Defaults.shared.exportLocaleId = id
            }

        case .process:
            self.process(in: viewModel)
        }
    }

    private func process(in viewModel: ViewModel<CitationBibliographyExportActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.isLoading = true
        }

        let format: CitationController.Format
        switch viewModel.state.method {
        case .copy:
            format = .text
        case .html:
            format = .html
        }

        let value: Single<String>

        switch viewModel.state.mode {
        case .citation:
            let itemIds = viewModel.state.itemIds
            let libraryId = viewModel.state.libraryId

            value = self.citationController.prepareForCitation(for: itemIds, libraryId: libraryId, styleId: viewModel.state.style.identifier, localeId: viewModel.state.localeId, in: self.webView)
                        .flatMap { self.citationController.citation(for: itemIds, libraryId: libraryId, label: nil, locator: nil, omitAuthor: false, format: format, in: self.webView) }

        case .bibliography:
            value = self.citationController.bibliography(for: viewModel.state.itemIds, libraryId: viewModel.state.libraryId, styleId: viewModel.state.style.identifier,
                                                         localeId: viewModel.state.localeId, format: format, in: self.webView)
        }

        value.subscribe(with: viewModel,
                        onSuccess: { viewModel, value in
                            self.finishProcessing(value: value, in: viewModel)
                        }, onFailure: { viewModel, error in
                            DDLogError("CitationBibliographyExportActionHandler: can't create citation of bibliography - \(error)")
                            self.update(viewModel: viewModel) { state in
                                state.isLoading = false
                                state.error = error
                            }
                        })
            .disposed(by: self.disposeBag)
    }

    private func finishProcessing(value: String, in viewModel: ViewModel<CitationBibliographyExportActionHandler>) {
        switch viewModel.state.method {
        case .copy:
            UIPasteboard.general.string = value

            self.update(viewModel: viewModel) { state in
                state.isLoading = false
                state.changes = .finished
            }

        case .html:
            let finish: (Result<File, Error>) -> Void = { result in
                DispatchQueue.main.async {
                    self.update(viewModel: viewModel) { state in
                        switch result {
                        case .success(let file):
                            state.outputFile = file
                        case .failure(let error):
                            DDLogError("CitationBibliographyExportActionHandler: can't finish citation of bibliography - \(error)")
                            state.error = error
                        }

                        state.isLoading = false
                    }
                }
            }

            self.queue.async {
                guard let data = value.data(using: .utf8) else {
                    finish(.failure(CitationBibliographyExportState.Error.cantCreateData))
                    return
                }

                let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("Untitled.html")
                let file = Files.file(from: url)

                do {
                    try self.fileStorage.write(data, to: file, options: [])
                    finish(.success(file))
                } catch let error {
                    finish(.failure(error))
                }
            }
        }
    }
}
