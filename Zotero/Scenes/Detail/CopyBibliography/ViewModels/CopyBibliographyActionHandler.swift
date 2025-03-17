//
//  CopyBibliographyActionHandler.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 27/12/23.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

import CocoaLumberjackSwift
import RxSwift

struct CopyBibliographyActionHandler: ViewModelActionHandler {
    typealias Action = CopyBibliographyAction
    typealias State = CopyBibliographyState

    private unowned let citationController: CitationController
    private let disposeBag = DisposeBag()

    init(citationController: CitationController) {
        self.citationController = citationController
    }

    func process(action: CopyBibliographyAction, in viewModel: ViewModel<CopyBibliographyActionHandler>) {
        switch action {
        case .preload(let webView):
            preload(webView: webView, in: viewModel)

        case .cleanup:
            citationController.finishCitation()
        }

        func preload(webView: WKWebView, in viewModel: ViewModel<CopyBibliographyActionHandler>) {
            update(viewModel: viewModel) { state in
                state.processingBibliography = true
            }

            let itemIds = viewModel.state.itemIds
            let libraryId = viewModel.state.libraryId
            let styleId = viewModel.state.styleId
            let localeId = viewModel.state.localeId
            let exportAsHtml = viewModel.state.exportAsHtml
            citationController.prepare(webView: webView, for: itemIds, libraryId: libraryId, styleId: styleId, localeId: localeId)
                .flatMap { _ -> Single<String> in
                    return citationController.bibliography(for: itemIds, format: .html)
                }
                .flatMap { html -> Single<(String, String?)> in
                    if exportAsHtml { return Single.just((html, nil)) }
                    return citationController.bibliography(for: itemIds, format: .text).flatMap({ Single.just((html, $0)) })
                }
                .subscribe(with: viewModel, onSuccess: { viewModel, data in
                    if let plaintext = data.1 {
                        UIPasteboard.general.copy(html: data.0, plaintext: plaintext)
                    } else {
                        UIPasteboard.general.string = data.0
                    }
                    update(viewModel: viewModel) { state in
                        state.processingBibliography = false
                    }
                }, onFailure: { viewModel, error in
                    DDLogError("CopyBibliographyActionHandler: could not load bibliography - \(error)")
                    update(viewModel: viewModel) { state in
                        state.processingBibliography = false
                        state.error = error
                    }
                })
                .disposed(by: disposeBag)
        }
    }
}
