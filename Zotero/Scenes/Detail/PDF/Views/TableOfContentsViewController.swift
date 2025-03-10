//
//  TableOfContentsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 19.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit
import RxSwift

class TableOfContentsViewController<O: Outline>: UIViewController, UICollectionViewDelegate {
    enum Section {
        case search, outline
    }

    private let viewModel: ViewModel<TableOfContentsActionHandler<O>>
    private let disposeBag: DisposeBag

    private weak var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, TableOfContentsState<O>.Row>?

    var selectionAction: (O) -> Void

    init(viewModel: ViewModel<TableOfContentsActionHandler<O>>, selectionAction: @escaping (O) -> Void) {
        self.viewModel = viewModel
        self.selectionAction = selectionAction
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .systemGray6

        if viewModel.state.outlines.isEmpty {
            setupEmptyView()
            return
        }

        setupCollectionView()
        setupDataSource()

        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe { [weak self] state in
                self?.update(state: state)
            }
            .disposed(by: self.disposeBag)

        viewModel.process(action: .load)

        func setupDataSource() {
            let outlineRegistration = self.outlineRegistration
            let searchRegistration = self.searchRegistration

            self.dataSource = UICollectionViewDiffableDataSource(collectionView: self.collectionView, cellProvider: { [weak self] collectionView, indexPath, row in
                switch row {
                case .searchBar:
                    return collectionView.dequeueConfiguredReusableCell(using: searchRegistration, for: indexPath, item: (self?.viewModel.state.search ?? ""))

                case .outline(let outline, let isActive):
                    return collectionView.dequeueConfiguredReusableCell(using: outlineRegistration, for: indexPath, item: (outline, isActive))
                }
            })

            var baseSnapshot = NSDiffableDataSourceSnapshot<Section, TableOfContentsState<O>.Row>()
            baseSnapshot.appendSections([.search, .outline])
            baseSnapshot.appendItems([.searchBar], toSection: .search)
            dataSource!.apply(baseSnapshot)
        }

        func setupCollectionView() {
            let collectionView = UICollectionView(frame: CGRect(), collectionViewLayout: createCollectionViewLayout())
            collectionView.translatesAutoresizingMaskIntoConstraints = false
            collectionView.delegate = self
            view.addSubview(collectionView)
            self.collectionView = collectionView

            NSLayoutConstraint.activate([
                collectionView.topAnchor.constraint(equalTo: view.topAnchor),
                collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
                collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])

            func createCollectionViewLayout() -> UICollectionViewCompositionalLayout {
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
    }

    // MARK: - State

    private func update(state: TableOfContentsState<O>) {
        if state.changes.contains(.snapshot), let snapshot = state.outlineSnapshot {
            dataSource?.apply(snapshot, to: .outline)
        }
    }

    // MARK: - Empty view

    private func setupEmptyView() {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.adjustsFontForContentSizeCategory = true
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .systemGray
        label.text = L10n.Pdf.Sidebar.noOutline
        label.setContentHuggingPriority(.defaultLow, for: .vertical)
        label.textAlignment = .center
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: view.topAnchor),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    // MARK: - Collection view

    private lazy var outlineRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, (O, Bool)> = {
        return UICollectionView.CellRegistration<UICollectionViewListCell, (O, Bool)> { [weak self] cell, _, data in
            guard let self = self, let dataSource = self.dataSource else { return }

            var configuration = cell.defaultContentConfiguration()
            configuration.text = data.0.title
            configuration.textProperties.color = data.1 ? .label : .systemGray
            cell.contentConfiguration = configuration

            let snapshot = dataSource.snapshot(for: .outline)
            let showToggle = viewModel.state.search.isEmpty &&
                            snapshot.contains(.outline(outline: data.0, isActive: data.1)) &&
                            !snapshot.snapshot(of: .outline(outline: data.0, isActive: data.1), includingParent: false).items.isEmpty
            cell.accessories = showToggle ? [.outlineDisclosure()] : []
        }
    }()

    private lazy var searchRegistration: UICollectionView.CellRegistration<SearchBarCell, String> = {
        return UICollectionView.CellRegistration<SearchBarCell, String> { [weak self] cell, _, string in
            cell.contentConfiguration = SearchBarCell.ContentConfiguration(text: string, changeAction: { [weak self] newText in
                self?.viewModel.process(action: .search(newText))
            })
        }
    }()

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let row = dataSource?.itemIdentifier(for: indexPath), case .outline(let outline, let isActive) = row, isActive else { return }
        selectionAction(outline)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard var snapshot = dataSource?.snapshot(for: .outline) else { return nil }

        let hasExpanded = snapshot.items.contains(where: { snapshot.isExpanded($0) })
        let hasCollapsed = snapshot.items.contains { row in
            if snapshot.snapshot(of: row, includingParent: false).items.isEmpty {
                return false
            }
            return !snapshot.isExpanded(row)
        }

        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            var actions: [UIAction] = []

            if hasCollapsed {
                actions.append(UIAction(title: L10n.Collections.expandAll, image: UIImage(systemName: "chevron.down")) { [weak self] _ in
                    snapshot.expand(snapshot.items)
                    self?.dataSource?.apply(snapshot, to: .outline)
                })
            }

            if hasExpanded {
                actions.append(UIAction(title: L10n.Collections.collapseAll, image: UIImage(systemName: "chevron.right")) { [weak self] _ in
                    snapshot.collapse(snapshot.items)
                    self?.dataSource?.apply(snapshot, to: .outline)
                })
            }

            return UIMenu(title: "", children: actions)
        })
    }
}
