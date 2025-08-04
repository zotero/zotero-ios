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
    private let queue: DispatchQueue
    private let disposeBag: DisposeBag

    weak var coordinatorDelegate: CitationBibliographyExportCoordinatorDelegate?

    init(citationController: CitationController, fileStorage: FileStorage) {
        self.citationController = citationController
        self.fileStorage = fileStorage
        queue = DispatchQueue(label: "org.zotero.CitationBibliographyExportActionHandler", qos: .userInteractive)
        disposeBag = DisposeBag()
    }

    func process(action: CitationBibliographyExportAction, in viewModel: ViewModel<CitationBibliographyExportActionHandler>) {
        switch action {
        case .setMethod(let method):
            update(viewModel: viewModel) { state in
                state.method = method
                Defaults.shared.exportOutputMethod = method
            }

        case .setMode(let mode):
            update(viewModel: viewModel) { state in
                state.mode = mode
                Defaults.shared.exportOutputMode = mode
            }

        case .setType(let type):
            update(viewModel: viewModel) { state in
                state.type = type
            }

        case .setStyle(let style):
            update(viewModel: viewModel) { state in
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
            update(viewModel: viewModel) { state in
                state.localeId = id
                state.localeName = name
                Defaults.shared.exportLocaleId = id
            }

        case .process:
            process(in: viewModel)
        }
    }

    private func process(in viewModel: ViewModel<CitationBibliographyExportActionHandler>) {
        update(viewModel: viewModel) { state in
            state.isLoading = true
        }

        switch viewModel.state.method {
        case .copy:
            loadForCopy(in: viewModel)
                .subscribe(onSuccess: { [weak viewModel] data in
                    guard let viewModel else { return }
                    copy(html: data.html, plainText: data.plainText, in: viewModel)
                }, onFailure: { [weak viewModel] error in
                    DDLogError("CitationBibliographyExportActionHandler: can't create citation of bibliography - \(error)")
                    guard let viewModel else { return }
                    handle(error: error, in: viewModel)
                }, onDisposed: { [weak viewModel] in
                    guard let viewModel else { return }
                    endCitationSession(in: viewModel)
                })
                .disposed(by: disposeBag)

        case .html:
            loadForHtml(in: viewModel)
                .subscribe(onSuccess: { [weak viewModel] html in
                    guard let viewModel else { return }
                    save(html: html, in: viewModel)
                }, onFailure: { [weak viewModel] error in
                    DDLogError("CitationBibliographyExportActionHandler: can't create citation of bibliography - \(error)")
                    guard let viewModel else { return }
                    handle(error: error, in: viewModel)
                }, onDisposed: { [weak viewModel] in
                    guard let viewModel else { return }
                    endCitationSession(in: viewModel)
                })
                .disposed(by: disposeBag)
        }

        func endCitationSession(in viewModel: ViewModel<CitationBibliographyExportActionHandler>) {
            guard let session = viewModel.state.citationSession else { return }
            citationController.endSession(session)
            update(viewModel: viewModel) { state in
                state.citationSession = nil
            }
        }
    }

    private func loadSession(in viewModel: ViewModel<CitationBibliographyExportActionHandler>) -> Single<CitationController.Session> {
        let state = viewModel.state
        if let session = state.citationSession {
            return .just(session)
        }
        return citationController.startSession(for: state.itemIds, libraryId: state.libraryId, styleId: state.style.identifier, localeId: state.localeId)
            .do(onSuccess: { [weak viewModel] session in
                guard let viewModel else { return }
                update(viewModel: viewModel) { state in
                    state.citationSession = session
                }
            })
    }

    private func loadForCopy(in viewModel: ViewModel<CitationBibliographyExportActionHandler>) -> Single<(html: String, plainText: String)> {
        return loadSession(in: viewModel).flatMap { session in
            return loadForHtml(in: viewModel).flatMap({ return .just((session, $0)) })
        }
        .flatMap { session, html in
            switch viewModel.state.mode {
            case .citation:
                return citationController.citation(for: session, label: nil, locator: nil, omitAuthor: false, format: .text, showInWebView: false)
                    .flatMap({ return .just((html, $0)) })

            case .bibliography:
                return citationController.bibliography(for: session, format: .text)
                    .flatMap({ return .just((html, $0)) })
            }
        }
    }

    private func loadForHtml(in viewModel: ViewModel<CitationBibliographyExportActionHandler>) -> Single<String> {
        return loadSession(in: viewModel).flatMap { session in
            switch viewModel.state.mode {
            case .citation:
                return citationController.citation(for: session, label: nil, locator: nil, omitAuthor: false, format: .html, showInWebView: false)

            case .bibliography:
                return citationController.bibliography(for: session, format: .html)
            }
        }
        .flatMap { html in
            return .just(CitationController.Format.html.wrapIfNeeeded(result: html))
        }
    }

    private func copy(html: String, plainText: String, in viewModel: ViewModel<CitationBibliographyExportActionHandler>) {
        UIPasteboard.general.copy(html: html, plainText: plainText)
        update(viewModel: viewModel) { state in
            state.isLoading = false
            state.changes = .finished
        }
    }

    private func save(html: String, in viewModel: ViewModel<CitationBibliographyExportActionHandler>) {
        let finish: (Result<File, Error>) -> Void = { result in
            DispatchQueue.main.async {
                update(viewModel: viewModel) { state in
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

        queue.async {
            guard let data = html.data(using: .utf8) else {
                finish(.failure(CitationBibliographyExportState.Error.cantCreateData))
                return
            }

            let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("Untitled.html")
            let file = Files.file(from: url)

            do {
                try fileStorage.write(data, to: file, options: [])
                finish(.success(file))
            } catch let error {
                finish(.failure(error))
            }
        }
    }

    private func handle(error: Error, in viewModel: ViewModel<CitationBibliographyExportActionHandler>) {
        update(viewModel: viewModel) { state in
            state.isLoading = false

            if let error = error as? CitationController.Error, error == .styleOrLocaleMissing {
                coordinatorDelegate?.showStylePicker(picked: { style in
                    viewModel.process(action: .setStyle(style))
                })
            } else {
                state.error = error
            }
        }
    }
}
