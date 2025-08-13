//
//  HtmlEpubSearchHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 13.08.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class HtmlEpubSearchHandler {
    private unowned let viewModel: ViewModel<HtmlEpubReaderActionHandler>
    private unowned let documentController: HtmlEpubDocumentViewController
    private let disposeBag: DisposeBag
    weak var delegate: DocumentSearchDataSourceDelegate?

    init(viewModel: ViewModel<HtmlEpubReaderActionHandler>, documentController: HtmlEpubDocumentViewController) {
        self.viewModel = viewModel
        self.documentController = documentController
        disposeBag = DisposeBag()

        viewModel.stateObservable
            .subscribe(onNext: { [weak self] state in
                self?.process(state: state)
            })
            .disposed(by: disposeBag)
    }

    private func process(state: HtmlEpubReaderState) {
        guard state.changes.contains(.searchResults) else { return }
        delegate?.stopSearchLoadingIndicator()
        delegate?.set(footer: L10n.Pdf.Search.matches(state.documentSearchResults.count))
        delegate?.dataChanged()
    }
}

extension HtmlEpubSearchHandler: DocumentSearchHandler {
    var count: Int {
        return viewModel.state.documentSearchResults.count
    }

    func result(at index: Int) -> DocumentSearchResult? {
        guard index < viewModel.state.documentSearchResults.count else { return nil }
        return viewModel.state.documentSearchResults[index]
    }

    func search(for string: String) {
        if string.isEmpty {
            documentController.clearSearch()
            delegate?.stopSearchLoadingIndicator()
            viewModel.process(action: .searchDocument(""))
            delegate?.set(footer: nil)
            return
        }

        delegate?.startSearchLoadingIndicator()
        viewModel.process(action: .searchDocument(string))
    }

    func select(index: Int) {
        documentController.selectSearchResult(index: index)
    }

    func cancel() {
    }
}
