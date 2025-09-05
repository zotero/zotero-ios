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

    init(snippet: String, highlightRange: NSRange, pageLabel: String? = nil) {
        self.snippet = snippet
        self.pageLabel = pageLabel
        self.highlightRange = highlightRange
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
            tableView.register(UINib(nibName: "DocumentSearchCell", bundle: nil), forCellReuseIdentifier: DocumentSearchViewController.cellId)
            view.addSubview(tableView)
            self.tableView = tableView

            let label = UILabel(frame: CGRect(x: 0, y: 0, width: tableView.frame.width, height: 44))
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = UIFont.preferredFont(forTextStyle: .footnote)
            label.textColor = .darkGray
            label.textAlignment = .center
            label.backgroundColor = .systemBackground
            view.addSubview(label)
            footerLabel = label

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
                tableView.bottomAnchor.constraint(equalTo: label.topAnchor),
                tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
                label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                label.heightAnchor.constraint(equalToConstant: 36)
            ])
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
        if let result = handler.result(at: indexPath.row), let cell = cell as? DocumentSearchCell {
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
