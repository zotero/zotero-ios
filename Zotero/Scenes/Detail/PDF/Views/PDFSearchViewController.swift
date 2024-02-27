//
//  PDFSearchViewController.swift
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

protocol PDFSearchDelegate: AnyObject {
    func didFinishSearch(with results: [SearchResult], for text: String?)
    func didSelectSearchResult(_ result: SearchResult)
}

final class PDFSearchViewController: UIViewController {
    weak var delegate: PDFSearchDelegate?

    private static let cellId = "SearchCell"
    private unowned let pdfController: PDFViewController
    private let disposeBag: DisposeBag

    private weak var tableView: UITableView!
    private weak var searchBar: UISearchBar!
    private var footerLabel: UILabel!

    private var currentSearch: TextSearch?
    private var results: [SearchResult]
    var text: String? {
        didSet {
            guard let text else {
                text = oldValue
                return
            }
            guard text != oldValue else { return }
            searchBar.text = text
            search(for: text)
        }
    }

    init(controller: PDFViewController, text: String?) {
        self.text = text
        pdfController = controller
        results = []
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()

        func setupViews() {
            let tableView = UITableView()
            tableView.translatesAutoresizingMaskIntoConstraints = false
            tableView.dataSource = self
            tableView.delegate = self
            tableView.keyboardDismissMode = UIDevice.current.userInterfaceIdiom == .pad ? .none : .onDrag
            tableView.register(UINib(nibName: "PDFSearchCell", bundle: nil), forCellReuseIdentifier: PDFSearchViewController.cellId)
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
        currentSearch?.cancelAllOperations()
    }

    deinit {
        DDLogInfo("PDFSearchViewController deinitialized")
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let key = presses.first?.key, key.keyCode == .keyboardEscape else {
            super.pressesBegan(presses, with: event)
            return
        }
        dismiss(animated: true, completion: nil)
    }

    // MARK: - Actions

    private func search(for string: String) {
        guard let document = pdfController.document else { return }

        if string.isEmpty {
            finishSearch(with: [])
            footerLabel.text = nil
        }

        let search = TextSearch(document: document)
        search.delegate = self
        search.comparisonOptions = [.caseInsensitive, .diacriticInsensitive]
        search.search(for: string)
        currentSearch = search
    }

    private func finishSearch(with results: [SearchResult]) {
        self.searchBar.isLoading = false
        self.results = results
        delegate?.didFinishSearch(with: results, for: text)
        self.tableView.reloadData()
    }
}

extension PDFSearchViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: PDFSearchViewController.cellId, for: indexPath)
        if indexPath.row < results.count, let cell = cell as? PDFSearchCell {
            cell.setup(with: results[indexPath.row])
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let result = indexPath.row < results.count ? results[indexPath.row] : nil

        dismiss(animated: true) { [weak self] in
            guard let result, let self else { return }
            delegate?.didSelectSearchResult(result)
        }
    }
}

extension PDFSearchViewController: TextSearchDelegate {
    func willStart(_ textSearch: TextSearch, term searchTerm: String, isFullSearch: Bool) {
        searchBar.isLoading = true
    }

    func didFinish(_ textSearch: TextSearch, term searchTerm: String, searchResults: [SearchResult], isFullSearch: Bool, pageTextFound: Bool) {
        finishSearch(with: searchResults)
        if searchTerm.isEmpty {
            footerLabel.text = nil
        } else {
            footerLabel.text = L10n.Pdf.Search.matches(searchResults.count)
        }
    }

    func didFail(_ textSearch: TextSearch, withError error: Error) {
        finishSearch(with: [])
        footerLabel.text = L10n.Pdf.Search.failed
    }

    func didCancel(_ textSearch: TextSearch, term searchTerm: String, isFullSearch: Bool) {
        searchBar.isLoading = false
    }
}

extension PDFSearchViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}
