//
//  SingleCitationActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 15.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import MobileCoreServices
import UIKit
import WebKit

import CocoaLumberjackSwift
import RxSwift

struct SingleCitationActionHandler: ViewModelActionHandler {
    typealias Action = SingleCitationAction
    typealias State = SingleCitationState

    private unowned let citationController: CitationController
    private let disposeBag: DisposeBag

    init(citationController: CitationController) {
        self.citationController = citationController
        disposeBag = DisposeBag()
    }

    func process(action: SingleCitationAction, in viewModel: ViewModel<SingleCitationActionHandler>) {
        switch action {
        case .preload(let webView):
            preload(webView: webView, in: viewModel)

        case .setLocator(let locator):
            loadPreview(
                locatorLabel: locator,
                locatorValue: viewModel.state.locatorValue,
                omitAuthor: viewModel.state.omitAuthor,
                stateAction: { state in
                    state.locator = locator
                    state.changes = [.preview, .locator]
                },
                in: viewModel
            )

        case .setLocatorValue(let value):
            loadPreview(
                locatorLabel: viewModel.state.locator,
                locatorValue: value,
                omitAuthor: viewModel.state.omitAuthor,
                stateAction: { state in
                    state.locatorValue = value
                    state.changes = .preview
                },
                in: viewModel
            )

        case .setOmitAuthor(let omitAuthor):
            loadPreview(
                locatorLabel: viewModel.state.locator,
                locatorValue: viewModel.state.locatorValue,
                omitAuthor: omitAuthor,
                stateAction: { state in
                    state.omitAuthor = omitAuthor
                    state.changes = .preview
                },
                in: viewModel
            )

        case .setPreviewHeight(let height):
            update(viewModel: viewModel) { state in
                state.previewHeight = height
                state.changes = .height
            }

        case .cleanup:
            guard let session = viewModel.state.citationSession else { return }
            citationController.endSession(session)
            update(viewModel: viewModel) { state in
                state.citationSession = nil
            }

        case .copy:
            copy(in: viewModel)
        }
    }

    private func copy(in viewModel: ViewModel<SingleCitationActionHandler>) {
        guard let preview = viewModel.state.preview else { return }
        let wrappedHTML = CitationController.Format.html.wrapIfNeeeded(result: preview)
        if viewModel.state.exportAsHtml {
            UIPasteboard.general.copy(html: wrappedHTML, plainText: preview)
            update(viewModel: viewModel) { state in
                state.changes = .copied
            }
            return
        }

        update(viewModel: viewModel) { state in
            state.loadingCopy = true
        }

        guard let session = viewModel.state.citationSession else { return }
        citationController.citation(
            for: session,
            label: viewModel.state.locator,
            locator: viewModel.state.locatorValue,
            omitAuthor: viewModel.state.omitAuthor,
            format: .text,
            showInWebView: false
        )
        .subscribe(onSuccess: { [weak viewModel] text in
            UIPasteboard.general.copy(html: wrappedHTML, plainText: text)
            guard let viewModel else { return }
            update(viewModel: viewModel) { state in
                state.loadingCopy = false
                state.changes = .copied
            }
        })
        .disposed(by: disposeBag)
    }

    private func loadPreview(
        locatorLabel: String,
        locatorValue: String,
        omitAuthor: Bool,
        stateAction: @escaping (inout SingleCitationState) -> Void,
        in viewModel: ViewModel<SingleCitationActionHandler>
    ) {
        guard let session = viewModel.state.citationSession else { return }
        citationController
            .citation(for: session, label: locatorLabel, locator: locatorValue, omitAuthor: omitAuthor, format: .html, showInWebView: true)
            .subscribe(onSuccess: { [weak viewModel] preview in
                guard let viewModel else { return }
                update(viewModel: viewModel) { state in
                    state.preview = preview
                    state.changes = .preview
                    stateAction(&state)
                }
            })
            .disposed(by: disposeBag)
    }

    private func preload(webView: WKWebView, in viewModel: ViewModel<SingleCitationActionHandler>) {
        let state = viewModel.state
        citationController.startSession(for: state.itemIds, libraryId: state.libraryId, styleId: state.styleId, localeId: state.localeId, webView: webView)
            .do(onSuccess: { [weak viewModel] session in
                guard let viewModel else { return }
                update(viewModel: viewModel) { state in
                    state.citationSession = session
                    state.changes = .webViewLoaded
                }
            })
            .flatMap { session -> Single<String> in
                return citationController.citation(for: session, label: state.locator, locator: state.locatorValue, omitAuthor: state.omitAuthor, format: .html, showInWebView: true)
            }
            .subscribe(
                onSuccess: { [weak viewModel] preview in
                    guard let viewModel else { return }
                    update(viewModel: viewModel) { state in
                        state.preview = preview
                        state.changes = .preview
                    }
                }, onFailure: { [weak viewModel] error in
                    DDLogError("SingleCitationActionHandler: can't preload webView - \(error)")
                    guard let viewModel else { return }
                    update(viewModel: viewModel) { state in
                        if let error = error as? CitationController.Error, error == .styleOrLocaleMissing {
                            state.error = .styleMissing
                        } else {
                            state.error = .cantPreloadWebView
                        }
                    }
                }
            )
            .disposed(by: disposeBag)
    }
}
