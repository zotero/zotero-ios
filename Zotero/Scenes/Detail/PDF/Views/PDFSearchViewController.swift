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
        self.pdfController = controller
        self.results = []
        self.text = text
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupViews()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.searchBar.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.currentSearch?.cancelAllOperations()
    }

    deinit {
        DDLogInfo("PDFSearchViewController deinitialized")
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let key = presses.first?.key, key.keyCode == .keyboardEscape else {
            super.pressesBegan(presses, with: event)
            return
        }
        self.dismiss(animated: true, completion: nil)
    }

    // MARK: - Actions

    private func search(for string: String) {
        guard let document = self.pdfController.document else { return }

        if string.isEmpty {
            self.finishSearch(with: [])
            self.footerLabel.text = nil
        }

        let search = TextSearch(document: document)
        search.delegate = self
        search.comparisonOptions = [.caseInsensitive, .diacriticInsensitive]
        search.search(for: string)
        self.currentSearch = search
    }

    private func finishSearch(with results: [SearchResult]) {
        self.searchBar.isLoading = false
        self.results = results
        delegate?.didFinishSearch(with: results, for: text)
        self.tableView.reloadData()
    }

    // MARK: - Setups

    private func setupViews() {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = UIDevice.current.userInterfaceIdiom == .pad ? .none : .interactive
        tableView.register(UINib(nibName: "PDFSearchCell", bundle: nil), forCellReuseIdentifier: PDFSearchViewController.cellId)
        self.view.addSubview(tableView)
        self.tableView = tableView

        let searchBar = UISearchBar()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.placeholder = L10n.Pdf.Search.title
        searchBar.rx.text.observe(on: MainScheduler.instance)
                         .skip(1)
                         .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                         .subscribe(onNext: { [weak self] text in
                             self?.text = text
                         })
                         .disposed(by: self.disposeBag)
        self.view.addSubview(searchBar)
        self.searchBar = searchBar

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor)
        ])

        let label = UILabel(frame: CGRect(x: 0, y: 0, width: tableView.frame.width, height: 44))
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textColor = .darkGray
        label.textAlignment = .center
        tableView.tableFooterView = label
        self.footerLabel = label
    }
}

extension PDFSearchViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: PDFSearchViewController.cellId, for: indexPath)
        if let cell = cell as? PDFSearchCell {
            let result = self.results[indexPath.row]
            cell.setup(with: result)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            delegate?.didSelectSearchResult(results[indexPath.row])
        }
    }
}

extension PDFSearchViewController: TextSearchDelegate {
    func willStart(_ textSearch: TextSearch, term searchTerm: String, isFullSearch: Bool) {
        self.searchBar.isLoading = true
    }

    func didFinish(_ textSearch: TextSearch, term searchTerm: String, searchResults: [SearchResult], isFullSearch: Bool, pageTextFound: Bool) {
        self.finishSearch(with: searchResults)

        if searchTerm.isEmpty {
            self.footerLabel.text = nil
        } else {
            self.footerLabel.text = L10n.Pdf.Search.matches(searchResults.count)
        }
    }

    func didFail(_ textSearch: TextSearch, withError error: Error) {
        self.finishSearch(with: [])
        self.footerLabel.text = L10n.Pdf.Search.failed
    }

    func didCancel(_ textSearch: TextSearch, term searchTerm: String, isFullSearch: Bool) {
        self.searchBar.isLoading = false
    }
}
