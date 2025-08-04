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
        case .preload:
            preload(in: viewModel)

        case .cleanup:
            guard let session = viewModel.state.citationSession else { return }
            citationController.endSession(session)
            update(viewModel: viewModel) { state in
                state.citationSession = nil
            }
        }

        func preload(in viewModel: ViewModel<CopyBibliographyActionHandler>) {
            update(viewModel: viewModel) { state in
                state.processingBibliography = true
            }

            let state = viewModel.state
            citationController.startSession(for: state.itemIds, libraryId: state.libraryId, styleId: state.styleId, localeId: state.localeId)
                .do(onSuccess: { [weak viewModel] session in
                    guard let viewModel else { return }
                    update(viewModel: viewModel) { state in
                        state.citationSession = session
                    }
                })
                .flatMap { session -> Single<(CitationController.Session, String)> in
                    return citationController.bibliography(for: session, format: .html).flatMap({ .just((session, $0)) })
                }
                .flatMap { session, html -> Single<(html: String, plainText: String)> in
                    let wrappedHTML = CitationController.Format.html.wrapIfNeeeded(result: html)
                    if state.exportAsHtml { return Single.just((wrappedHTML, html)) }
                    return citationController.bibliography(for: session, format: .text).flatMap({ Single.just((wrappedHTML, $0)) })
                }
                .subscribe(with: viewModel, onSuccess: { viewModel, data in
                    UIPasteboard.general.copy(html: data.html, plainText: data.plainText)
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
