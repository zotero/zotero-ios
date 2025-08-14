//
//  PDFSearchHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 13.08.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit

final class PDFSearchHandler: NSObject {
    private let document: PSPDFKit.Document
    private unowned let documentController: PDFDocumentViewController

    private var currentSearch: TextSearch?
    private var results: [SearchResult]
    weak var delegate: DocumentSearchDataSourceDelegate?

    init(document: PSPDFKit.Document, documentController: PDFDocumentViewController) {
        self.document = document
        self.documentController = documentController
        results = []
        super.init()
    }
}

extension PDFSearchHandler: DocumentSearchHandler {
    var count: Int {
        return results.count
    }

    func result(at index: Int) -> DocumentSearchResult? {
        guard index >= 0 && index < results.count else { return nil }
        return DocumentSearchResult(pdfResult: results[index])
    }

    func search(for string: String) {
        if string.isEmpty {
            finishSearch(with: [])
            delegate?.set(footer: nil)
        }

        let search = TextSearch(document: document)
        search.delegate = self
        search.comparisonOptions = [.caseInsensitive, .diacriticInsensitive]
        search.search(for: string)
        currentSearch = search
    }

    func select(index: Int) {
        guard index < results.count else { return }
        documentController.highlightSelectedSearchResult(results[index])
    }

    private func finishSearch(with results: [SearchResult]) {
        delegate?.stopSearchLoadingIndicator()
        self.results = results
        documentController.highlightSearchResults(results)
        delegate?.dataChanged()
    }

    func cancel() {
        currentSearch?.cancelAllOperations()
    }
}

extension PDFSearchHandler: TextSearchDelegate {
    func willStart(_ textSearch: TextSearch, term searchTerm: String, isFullSearch: Bool) {
        delegate?.startSearchLoadingIndicator()
    }

    func didFinish(_ textSearch: TextSearch, term searchTerm: String, searchResults: [SearchResult], isFullSearch: Bool, pageTextFound: Bool) {
        finishSearch(with: searchResults)
        if searchTerm.isEmpty {
            delegate?.set(footer: nil)
        } else {
            delegate?.set(footer: L10n.Pdf.Search.matches(searchResults.count))
        }
    }

    func didFail(_ textSearch: TextSearch, withError error: Error) {
        finishSearch(with: [])
        delegate?.set(footer: L10n.Pdf.Search.failed)
    }

    func didCancel(_ textSearch: TextSearch, term searchTerm: String, isFullSearch: Bool) {
        delegate?.stopSearchLoadingIndicator()
    }
}
