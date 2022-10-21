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
    enum Section {
        case search, outline
    }

    enum Row: Hashable {
        case searchBar
        case outline(TableOfContentsState.Outline)
    }

    private let viewModel: ViewModel<TableOfContentsActionHandler>
    private let disposeBag: DisposeBag

    private weak var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>?

    var selectionAction: (UInt) -> Void

    init(viewModel: ViewModel<TableOfContentsActionHandler>, selectionAction: @escaping (UInt) -> Void) {
        self.viewModel = viewModel
        self.selectionAction = selectionAction
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .systemGray6

        if (self.viewModel.state.document.outline?.children ?? []).isEmpty {
            self.setupEmptyView()
            return
        }

        self.setupCollectionView()
        self.setupDataSource()

        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe { [weak self] state in
                          self?.update(state: state)
                      }
                      .disposed(by: self.disposeBag)

        self.viewModel.process(action: .load)
    }

    // MARK: - State

    private func update(state: TableOfContentsState) {
        if state.changes.contains(.snapshot), let snapshot = state.outlineSnapshot {
            self.dataSource?.apply(snapshot, to: .outline)
        }
    }

    // MARK: - Empty view

    private func setupEmptyView() {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .systemGray
        label.text = L10n.Pdf.Sidebar.noOutline
        label.setContentHuggingPriority(.defaultLow, for: .vertical)
        label.textAlignment = .center
        self.view.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: self.view.topAnchor),
            label.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
        ])
    }

    // MARK: - Collection view

    private lazy var outlineRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, TableOfContentsState.Outline> = {
        return UICollectionView.CellRegistration<UICollectionViewListCell, TableOfContentsState.Outline> { [weak self] cell, indexPath, outline in
            guard let `self` = self, let dataSource = self.dataSource else { return }

            var configuration = cell.defaultContentConfiguration()
            configuration.text = outline.title
            configuration.textProperties.color = outline.isActive ? .label : .systemGray
            cell.contentConfiguration = configuration

            let snapshot = dataSource.snapshot(for: .outline)
            let showToggle = self.viewModel.state.search.isEmpty && snapshot.contains(.outline(outline)) && snapshot.snapshot(of: .outline(outline), includingParent: false).items.count > 0
            cell.accessories = showToggle ? [.outlineDisclosure()] : []
        }
    }()

    private lazy var searchRegistration: UICollectionView.CellRegistration<SearchBarCell, String> = {
        return UICollectionView.CellRegistration<SearchBarCell, String> { [weak self] cell, indexPath, string in
            cell.contentConfiguration = SearchBarCell.ContentConfiguration(text: string, changeAction: { [weak self] newText in
                self?.viewModel.process(action: .search(newText))
            })
        }
    }()

    private func setupDataSource() {
        let outlineRegistration = self.outlineRegistration
        let searchRegistration = self.searchRegistration

        self.dataSource = UICollectionViewDiffableDataSource(collectionView: self.collectionView, cellProvider: { [weak self] collectionView, indexPath, row in
            switch row {
            case .searchBar:
                return collectionView.dequeueConfiguredReusableCell(using: searchRegistration, for: indexPath, item: (self?.viewModel.state.search ?? ""))
            case .outline(let outline):
                return collectionView.dequeueConfiguredReusableCell(using: outlineRegistration, for: indexPath, item: outline)
            }
        })

        var baseSnapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        baseSnapshot.appendSections([.search, .outline])
        baseSnapshot.appendItems([.searchBar], toSection: .search)
        self.dataSource!.apply(baseSnapshot)
    }

    private func setupCollectionView() {
        let collectionView = UICollectionView(frame: CGRect(), collectionViewLayout: self.createCollectionViewLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        self.view.addSubview(collectionView)
        self.collectionView = collectionView

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: self.view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
    }

    private func createCollectionViewLayout() -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { section, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            configuration.showsSeparators = true
            configuration.backgroundColor = .systemGray6
            configuration.headerMode = .none

            let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: PDFReaderLayout.annotationLayout.horizontalInset, bottom: 0, trailing: PDFReaderLayout.annotationLayout.horizontalInset)
            return section
        }
    }
}

extension TableOfContentsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        guard let row = self.dataSource?.itemIdentifier(for: indexPath), case .outline(let outline) = row, outline.isActive else { return }
        self.selectionAction(outline.page)
    }
}

#endif
