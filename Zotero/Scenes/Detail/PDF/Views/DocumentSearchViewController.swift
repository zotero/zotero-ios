//
//  DocumentSearchViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 08/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import PSPDFKit
import PSPDFKitUI
import RxSwift

protocol DocumentSearchDataSourceDelegate: AnyObject {
    func startSearchLoadingIndicator()
    func stopSearchLoadingIndicator()
    func set(footer: String?)
    func dataChanged()
}

struct DocumentSearchResult {
    let pageLabel: String?
    let snippet: String
    let highlightRange: NSRange

    init(pdfResult: SearchResult) {
        pageLabel = "\(pdfResult.pageIndex + 1)"
        snippet = pdfResult.previewText
        highlightRange = pdfResult.rangeInPreviewText
    }
}

protocol DocumentSearchHandler: AnyObject {
    var delegate: DocumentSearchDataSourceDelegate? { get set }
    var count: Int { get }

    func result(at index: Int) -> DocumentSearchResult?
    func search(for string: String)
    func select(index: Int)
    func cancel()
}

final class HtmlEpubSearchHandler {
    private unowned let viewModel: ViewModel<HtmlEpubReaderActionHandler>
    private unowned let documentController: HtmlEpubDocumentViewController
    weak var delegate: DocumentSearchDataSourceDelegate?

    init(viewModel: ViewModel<HtmlEpubReaderActionHandler>, documentController: HtmlEpubDocumentViewController) {
        self.viewModel = viewModel
        self.documentController = documentController
    }
}

extension HtmlEpubSearchHandler: DocumentSearchHandler {
    var count: Int {
        // TODO
        return 0
    }
    
    func result(at index: Int) -> DocumentSearchResult? {
        // TODO
        return nil
    }
    
    func search(for string: String) {
        // TODO
    }
    
    func select(index: Int) {
        // TODO
    }
    
    func cancel() {
    }
}

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

final class DocumentSearchViewController: UIViewController {
    private static let cellId = "SearchCell"
    private let disposeBag: DisposeBag

    private var handler: DocumentSearchHandler
    private weak var tableView: UITableView!
    private weak var searchBar: UISearchBar!
    private var footerLabel: UILabel!

    var text: String? {
        didSet {
            guard let text else {
                text = oldValue
                return
            }
            guard text != oldValue else { return }
            searchBar.text = text
            handler.search(for: text)
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        [.init(title: L10n.Pdf.Search.dismiss, action: #selector(dismissSearch), input: UIKeyCommand.inputEscape)]
    }

    init(text: String?, handler: DocumentSearchHandler) {
        self.text = text
        self.handler = handler
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
        handler.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        if let text {
            searchBar.text = text
            handler.search(for: text)
        }

        func setupViews() {
            let tableView = UITableView()
            tableView.translatesAutoresizingMaskIntoConstraints = false
            tableView.dataSource = self
            tableView.delegate = self
            tableView.keyboardDismissMode = UIDevice.current.userInterfaceIdiom == .pad ? .none : .onDrag
            tableView.register(UINib(nibName: "PDFSearchCell", bundle: nil), forCellReuseIdentifier: DocumentSearchViewController.cellId)
            view.addSubview(tableView)
            self.tableView = tableView

            let searchBar = UISearchBar()
            searchBar.translatesAutoresizingMaskIntoConstraints = false
            searchBar.placeholder = L10n.Pdf.Search.title
            // Set search bar delegate before reactive extension, otherwise reactive will be overwritten.
            searchBar.delegate = self
            searchBar.rx
                .text
                .observe(on: MainScheduler.instance)
                .skip(1)
                .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                .subscribe(onNext: { [weak self] text in
                    self?.text = text
                })
                .disposed(by: disposeBag)
            view.addSubview(searchBar)
            self.searchBar = searchBar

            NSLayoutConstraint.activate([
                searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
                tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor)
            ])

            let label = UILabel(frame: CGRect(x: 0, y: 0, width: tableView.frame.width, height: 44))
            label.font = UIFont.preferredFont(forTextStyle: .footnote)
            label.textColor = .darkGray
            label.textAlignment = .center
            tableView.tableFooterView = label
            footerLabel = label
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        searchBar.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        handler.cancel()
    }

    deinit {
        DDLogInfo("PDFSearchViewController deinitialized")
    }

    // MARK: - Actions

    @objc private func dismissSearch() {
        dismiss(animated: true)
    }
}

extension DocumentSearchViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return handler.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DocumentSearchViewController.cellId, for: indexPath)
        if let result = handler.result(at: indexPath.row), let cell = cell as? PDFSearchCell {
            cell.setup(with: result)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        dismiss(animated: true) {
            self.handler.select(index: indexPath.row)
        }
    }
}

extension DocumentSearchViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

extension DocumentSearchViewController: DocumentSearchDataSourceDelegate {
    func startSearchLoadingIndicator() {
        searchBar.isLoading = true
    }
    
    func stopSearchLoadingIndicator() {
        searchBar.isLoading = false
    }
    
    func set(footer: String?) {
        footerLabel.text = footer
    }
    
    func dataChanged() {
        tableView.reloadData()
    }
}
