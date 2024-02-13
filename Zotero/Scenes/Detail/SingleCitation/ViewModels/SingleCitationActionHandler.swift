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

        case .setLocator(let locator, let webView):
            loadPreview(
                locatorLabel: locator,
                locatorValue: viewModel.state.locatorValue,
                omitAuthor: viewModel.state.omitAuthor,
                stateAction: { state in
                    state.locator = locator
                    state.changes = [.preview, .locator]
                },
                webView: webView,
                in: viewModel
            )

        case .setLocatorValue(let value, let webView):
            loadPreview(
                locatorLabel: viewModel.state.locator,
                locatorValue: value,
                omitAuthor: viewModel.state.omitAuthor,
                stateAction: { state in
                    state.locatorValue = value
                    state.changes = .preview
                },
                webView: webView,
                in: viewModel
            )

        case .setOmitAuthor(let omitAuthor, let webView):
            loadPreview(
                locatorLabel: viewModel.state.locator,
                locatorValue: viewModel.state.locatorValue,
                omitAuthor: omitAuthor,
                stateAction: { state in
                    state.omitAuthor = omitAuthor
                    state.changes = .preview
                },
                webView: webView,
                in: viewModel
            )

        case .setPreviewHeight(let height):
            update(viewModel: viewModel) { state in
                state.previewHeight = height
                state.changes = .height
            }

        case .cleanup:
            citationController.finishCitation()

        case .copy(let webView):
            copy(webView: webView, in: viewModel)
        }
    }

    private func copy(webView: WKWebView, in viewModel: ViewModel<SingleCitationActionHandler>) {
        guard let preview = viewModel.state.preview else { return }

        if viewModel.state.exportAsHtml {
            UIPasteboard.general.string = preview
            update(viewModel: viewModel) { state in
                state.changes = .copied
            }
            return
        }

        update(viewModel: viewModel) { state in
            state.loadingCopy = true
        }

        citationController.citation(
            for: viewModel.state.itemIds,
            label: viewModel.state.locator,
            locator: viewModel.state.locatorValue,
            omitAuthor: viewModel.state.omitAuthor,
            format: .text,
            showInWebView: false,
            in: webView
        )
        .subscribe(onSuccess: { [weak viewModel] text in
            UIPasteboard.general.copy(html: preview, plaintext: text)
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
        webView: WKWebView,
        in viewModel: ViewModel<SingleCitationActionHandler>
    ) {
        citationController
            .citation(for: viewModel.state.itemIds, label: locatorLabel, locator: locatorValue, omitAuthor: omitAuthor, format: .html, showInWebView: true, in: webView)
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
        let itemIds = viewModel.state.itemIds
        let libraryId = viewModel.state.libraryId
        citationController
            .prepare(webView: webView, for: itemIds, libraryId: libraryId, styleId: viewModel.state.styleId, localeId: viewModel.state.localeId)
            .flatMap({ [weak webView] _ -> Single<String> in
                guard let webView else { return Single.error(CitationController.Error.prepareNotCalled) }
                return citationController.citation(
                    for: itemIds,
                    label: viewModel.state.locator,
                    locator: viewModel.state.locatorValue,
                    omitAuthor: viewModel.state.omitAuthor,
                    format: .html,
                    showInWebView: true,
                    in: webView
                )
            })
            .subscribe(
                onSuccess: { [weak viewModel] preview in
                    guard let viewModel else { return }
                    update(viewModel: viewModel) { state in
                        state.preview = preview
                        state.changes = .preview
                    }
                }, onFailure: { [weak viewModel] error in
                    DDLogError("CitationActionHandler: can't preload webView - \(error)")
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
