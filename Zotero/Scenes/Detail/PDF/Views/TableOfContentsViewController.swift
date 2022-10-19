//
//  TableOfContentsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 19.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import PSPDFKit
import RxSwift

class TableOfContentsViewController: UIViewController {
    struct Outline: Hashable {
        let title: String
        let page: UInt

        init(element: OutlineElement) {
            self.title = element.title ?? ""
            self.page = element.pageIndex
        }
    }

    private let snapshot: NSDiffableDataSourceSectionSnapshot<Outline>?
    private let disposeBag: DisposeBag

    private weak var tableView: UITableView!
    private var dataSource: UITableViewDiffableDataSource<Int, Outline>!

    init(document: Document) {
        self.snapshot = TableOfContentsViewController.createSnapshot(from: document)
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .systemGray6
        self.setupTableView()
        self.setupSearchController()
        self.setupDataSource()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    private func setupDataSource() {
        self.dataSource = UITableViewDiffableDataSource(tableView: self.tableView, cellProvider: { tableView, indexPath, outline in
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

            cell.textLabel?.text = outline.title

            return cell
        })
    }

    private func setupTableView() {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGray6
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        self.view.addSubview(tableView)
        self.tableView = tableView

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: self.view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
    }

    private func setupSearchController() {
        let insets = UIEdgeInsets(top: PDFReaderLayout.searchBarVerticalInset,
                                  left: PDFReaderLayout.annotationLayout.horizontalInset,
                                  bottom: PDFReaderLayout.searchBarVerticalInset - PDFReaderLayout.cellSelectionLineWidth,
                                  right: PDFReaderLayout.annotationLayout.horizontalInset)

        var frame = self.tableView.frame
        frame.size.height = 65

        let searchBar = SearchBar(frame: frame, insets: insets, cornerRadius: 10)
        searchBar.text.observe(on: MainScheduler.instance)
                                .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                                .subscribe(onNext: { [weak self] text in
                                    self?.viewModel.process(action: .searchAnnotations(text))
                                })
                                .disposed(by: self.disposeBag)
        self.tableView.tableHeaderView = searchBar
    }

    private static func createSnapshot(from document: Document) -> NSDiffableDataSourceSectionSnapshot<Outline>? {
        guard let outlines = document.outline?.children else { return nil }

        var snapshot = NSDiffableDataSourceSectionSnapshot<Outline>()
        self.append(outlines: outlines, parent: nil, to: snapshot)
        return snapshot
    }

    private static func append(outlines: [OutlineElement], parent: Outline?, to snapshot: NSDiffableDataSourceSectionSnapshot<Outline>) {
        let _outlines = outlines.map(Outline.init)
        snapshot.append(_outlines, to: parent)

        for (idx, outline) in outlines.enumerated() {
            guard let children = outline.children else { continue }
            self.append(outlines: children, parent: _outlines[idx], to: snapshot)
        }
    }
}

#endif
