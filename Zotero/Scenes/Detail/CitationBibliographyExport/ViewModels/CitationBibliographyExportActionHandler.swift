//
//  CitationBibliographyExportActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 29.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import MobileCoreServices
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

    weak var coordinatorDelegate: CitationBibliographyExportCoordinatorDelegate?

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

        switch viewModel.state.method {
        case .copy:
            self.loadForCopy(in: viewModel)
                .subscribe(with: viewModel, onSuccess: { viewModel, data in
                    self.copy(html: data.0, plaintext: data.1, in: viewModel)
                    self.citationController.finishCitation()
                }, onFailure: { viewModel, error in
                    DDLogError("CitationBibliographyExportActionHandler: can't create citation of bibliography - \(error)")
                    self.handle(error: error, in: viewModel)
                    self.citationController.finishCitation()
                })
                .disposed(by: self.disposeBag)

        case .html:
            self.loadForHtml(in: viewModel)
                .subscribe(with: viewModel, onSuccess: { viewModel, html in
                    self.save(html: html, in: viewModel)
                    self.citationController.finishCitation()
                }, onFailure: { viewModel, error in
                    DDLogError("CitationBibliographyExportActionHandler: can't create citation of bibliography - \(error)")
                    self.handle(error: error, in: viewModel)
                    self.citationController.finishCitation()
                })
                .disposed(by: self.disposeBag)
        }
    }

    private func loadForCopy(in viewModel: ViewModel<CitationBibliographyExportActionHandler>) -> Single<(String, String)> {
        let itemIds = viewModel.state.itemIds

        switch viewModel.state.mode {
        case .citation:
            return self.loadForHtml(in: viewModel)
                       .flatMap { html -> Single<(String, String)> in
                           return self.citationController.citation(for: itemIds, label: nil, locator: nil, omitAuthor: false, format: .text, showInWebView: false, in: self.webView)
                                                         .flatMap({ return Single.just((html, $0)) })
                       }

        case .bibliography:
            return self.loadForHtml(in: viewModel)
                       .flatMap { html -> Single<(String, String)> in
                        return self.citationController.bibliography(for: itemIds, format: .text, in: self.webView).flatMap({ return Single.just((html, $0)) })
                       }
        }
    }

    private func loadForHtml(in viewModel: ViewModel<CitationBibliographyExportActionHandler>) -> Single<String> {
        let itemIds = viewModel.state.itemIds
        let libraryId = viewModel.state.libraryId

        let prepare: Single<()> = self.citationController.prepare(webView: self.webView, for: itemIds, libraryId: libraryId,
                                                                  styleId: viewModel.state.style.identifier, localeId: viewModel.state.localeId)

        switch viewModel.state.mode {
        case .citation:
            return prepare.flatMap { self.citationController.citation(for: itemIds, label: nil, locator: nil, omitAuthor: false, format: .html, showInWebView: false, in: self.webView) }

        case .bibliography:
            return prepare.flatMap { self.citationController.bibliography(for: itemIds, format: .html, in: self.webView) }
        }
    }

    private func copy(html: String, plaintext: String, in viewModel: ViewModel<CitationBibliographyExportActionHandler>) {
        UIPasteboard.general.copy(html: html, plaintext: plaintext)
        self.update(viewModel: viewModel) { state in
            state.isLoading = false
            state.changes = .finished
        }
    }

    private func save(html: String, in viewModel: ViewModel<CitationBibliographyExportActionHandler>) {
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
            guard let data = html.data(using: .utf8) else {
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

    private func handle(error: Error, in viewModel: ViewModel<CitationBibliographyExportActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.isLoading = false

            if let error = error as? CitationController.Error, error == .styleOrLocaleMissing {
                self.coordinatorDelegate?.showStylePicker(picked: { style in
                    viewModel.process(action: .setStyle(style))
                })
            } else {
                state.error = error
            }
        }
    }
}
