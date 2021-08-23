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
        self.disposeBag = DisposeBag()
    }

    func process(action: SingleCitationAction, in viewModel: ViewModel<SingleCitationActionHandler>) {
        switch action {
        case .preload(let webView):
            self.preload(webView: webView, in: viewModel)

        case .setLocator(let locator):
            self.loadPreview(locatorLabel: locator, locatorValue: viewModel.state.locatorValue, omitAuthor: viewModel.state.omitAuthor, stateAction: { state in
                state.locator = locator
                state.changes = [.preview, .locator]
            }, in: viewModel)

        case .setLocatorValue(let value):
            self.loadPreview(locatorLabel: viewModel.state.locator, locatorValue: value, omitAuthor: viewModel.state.omitAuthor, stateAction: { state in
                state.locatorValue = value
                state.changes = .preview
            }, in: viewModel)

        case .setOmitAuthor(let omitAuthor):
            self.loadPreview(locatorLabel: viewModel.state.locator, locatorValue: viewModel.state.locatorValue, omitAuthor: omitAuthor, stateAction: { state in
                state.omitAuthor = omitAuthor
                state.changes = .preview
            }, in: viewModel)

        case .cleanup:
            self.citationController.finishCitation()

        case .copy:
            self.copy(in: viewModel)
        }
    }

    private func copy(in viewModel: ViewModel<SingleCitationActionHandler>) {
        if viewModel.state.exportAsHtml {
            UIPasteboard.general.string = viewModel.state.preview
            self.update(viewModel: viewModel) { state in
                state.changes = .copied
            }
            return
        }

        guard let webView = viewModel.state.webView else {
            self.update(viewModel: viewModel) { state in
                state.error = .cantPreloadWebView
            }
            return
        }

        self.update(viewModel: viewModel) { state in
            state.loadingCopy = true
        }

        self.citationController.citation(for: viewModel.state.itemIds, libraryId: viewModel.state.libraryId, label: viewModel.state.locator, locator: viewModel.state.locatorValue,
                                         omitAuthor: viewModel.state.omitAuthor, format: .text, showInWebView: false, in: webView)
            .subscribe(with: viewModel, onSuccess: { viewModel, text in
                self.copy(html: viewModel.state.preview, plaintext: text)
                self.update(viewModel: viewModel) { state in
                    state.loadingCopy = false
                    state.changes = .copied
                }
            })
            .disposed(by: self.disposeBag)
    }

    private func copy(html: String, plaintext: String) {
        guard let htmlData = html.data(using: .utf8) else { return }
        UIPasteboard.general.items = [
            [(kUTTypePlainText as String): plaintext,
            (kUTTypeHTML as String): htmlData]
        ]
    }

    private func loadPreview(locatorLabel: String, locatorValue: String, omitAuthor: Bool, stateAction: @escaping (inout SingleCitationState) -> Void,
                             in viewModel: ViewModel<SingleCitationActionHandler>) {
        guard let webView = viewModel.state.webView else { return }
        self.citationController.citation(for: viewModel.state.itemIds, libraryId: viewModel.state.libraryId, label: locatorLabel, locator: locatorValue,
                                         omitAuthor: omitAuthor, format: .html, showInWebView: true, in: webView)
                               .subscribe(with: viewModel, onSuccess: { viewModel, preview in
                                   self.update(viewModel: viewModel) { state in
                                       state.preview = preview
                                       state.changes = .preview
                                       stateAction(&state)
                                   }
                               })
                               .disposed(by: self.disposeBag)
    }

    private func preload(webView: WKWebView, in viewModel: ViewModel<SingleCitationActionHandler>) {
        let itemIds = viewModel.state.itemIds
        let libraryId = viewModel.state.libraryId

        self.citationController.prepare(webView: webView, for: itemIds, libraryId: libraryId, styleId: viewModel.state.styleId, localeId: viewModel.state.localeId)
                               .flatMap({ [weak webView] _ -> Single<String> in
                                   guard let webView = webView else { return Single.error(CitationController.Error.prepareNotCalled) }
                                   return self.citationController.citation(for: itemIds, libraryId: libraryId, label: viewModel.state.locator, locator: viewModel.state.locatorValue,
                                                                           omitAuthor: viewModel.state.omitAuthor, format: .html, showInWebView: true, in: webView)
                               })
                               .subscribe(onSuccess: { [weak viewModel, weak webView] preview in
                                   guard let viewModel = viewModel else { return }
                                   self.update(viewModel: viewModel) { state in
                                       state.webView = webView
                                       state.preview = preview
                                       state.loadingPreview = false
                                       state.changes = .preview
                                   }
                               }, onFailure: { error in
                                   DDLogError("CitationActionHandler: can't preload webView - \(error)")

                                   self.update(viewModel: viewModel) { state in
                                       if let error = error as? CitationController.Error, error == .styleOrLocaleMissing {
                                           state.error = .styleMissing
                                       } else {
                                           state.error = .cantPreloadWebView
                                       }
                                   }
                               })
                               .disposed(by: self.disposeBag)
    }
}
