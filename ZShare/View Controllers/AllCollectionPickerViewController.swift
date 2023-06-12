//
//  AllCollectionPickerViewController.swift
//  ZShare
//
//  Created by Michal Rentka on 11.02.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class AllCollectionPickerViewController: UICollectionViewController {
    private enum Row: Hashable {
        case library(Library)
        case collection(Collection)
    }

    private let viewModel: ViewModel<AllCollectionPickerActionHandler>
    private let disposeBag: DisposeBag

    private var dataSource: UICollectionViewDiffableDataSource<LibraryIdentifier, Row>!
    var pickedAction: ((Collection?, Library) -> Void)?

    init(viewModel: ViewModel<AllCollectionPickerActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()
        super.init(collectionViewLayout: UICollectionViewFlowLayout())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.collectionView.collectionViewLayout = self.createCollectionViewLayout()
        self.dataSource = self.createDataSource(for: self.collectionView)
        self.setupSearchController()
        self.viewModel.process(action: .loadData)
        self.updateDataSource(with: self.viewModel.state, includeSelection: true)

        self.viewModel.stateObservable
                      .skip(1)
                      .observe(on: MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(to: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    // MARK: - State

    private func update(to state: AllCollectionPickerState) {
        if state.changes.contains(.results) {
            self.updateDataSource(with: state, includeSelection: false)
        }

        if state.changes.contains(.search), let controller = self.navigationItem.searchController?.searchResultsController as? SearchResultsController {
            self.update(searchResultsController: controller, with: state)
        }

        if let libraryId = state.toggledLibraryId, let collapsed = state.librariesCollapsed[libraryId] {
            self.update(collapsed: collapsed, for: libraryId)
        }

        if let libraryId = state.toggledCollectionInLibraryId {
            self.updateCollapsed(for: libraryId, state: state)
        }
    }

    private func updateDataSource(with state: AllCollectionPickerState, includeSelection: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<LibraryIdentifier, Row>()
        snapshot.appendSections(state.libraries.map({ $0.identifier }))
        self.dataSource.apply(snapshot, animatingDifferences: false)

        for library in state.libraries {
            guard let tree = state.trees[library.identifier], let collapsed = state.librariesCollapsed[library.identifier] else { continue }
            var snapshot = tree.createMappedSnapshot(mapping: { Row.collection($0) }, selectedId: (includeSelection ? state.selectedCollectionId : nil), parent: .library(library))
            if collapsed {
                snapshot.collapse([.library(library)])
            } else {
                snapshot.expand([.library(library)])
            }
            self.dataSource.apply(snapshot, to: library.identifier, animatingDifferences: false)
        }
    }

    private func update(searchResultsController: SearchResultsController, with state: AllCollectionPickerState) {
        var snapshot = NSDiffableDataSourceSnapshot<LibraryIdentifier, SearchResultsController.Row>()
        snapshot.appendSections(state.libraries.map({ $0.identifier }))
        searchResultsController.dataSource.apply(snapshot, animatingDifferences: false)

        for library in state.libraries {
            guard let tree = state.trees[library.identifier] else { continue }
            var snapshot = tree.createMappedSearchSnapshot(mapping: { SearchResultsController.Row.collection($0) }, parent: .library(library))
            snapshot.expand(snapshot.items)
            searchResultsController.dataSource.apply(snapshot, to: library.identifier, animatingDifferences: false)
        }
    }

    private func update(collapsed: Bool, for libraryId: LibraryIdentifier) {
        var snapshot = self.dataSource.snapshot(for: libraryId)

        guard let libraryRow = snapshot.items.first else { return }

        if collapsed {
            snapshot.collapse([libraryRow])
        } else {
            snapshot.expand([libraryRow])
        }

        self.dataSource.apply(snapshot, to: libraryId, animatingDifferences: true)
    }

    private func updateCollapsed(for libraryId: LibraryIdentifier, state: AllCollectionPickerState) {
        guard let tree = state.trees[libraryId], let libraryRow = self.dataSource.snapshot(for: libraryId).items.first else { return }

        var snapshot = tree.createMappedSnapshot(mapping: { Row.collection($0) }, selectedId: nil, parent: libraryRow)
        if let row = snapshot.items.first {
            snapshot.expand([row])
        }

        self.dataSource.apply(snapshot, to: libraryId, animatingDifferences: false)
    }

    private func picked(collection: Collection?, library: Library) {
        self.pickedAction?(collection, library)
        self.navigationController?.popViewController(animated: true)
    }

    private func picked(collection: Collection?, libraryId: LibraryIdentifier) {
        guard let library = self.viewModel.state.libraries.first(where: { $0.identifier == libraryId }) else { return }
        self.picked(collection: collection, library: library)
    }

    // MARK: - Data Source

    private lazy var cellRegistration: UICollectionView.CellRegistration<CollectionCell, Row> = {
        return UICollectionView.CellRegistration<CollectionCell, Row> { [weak self] cell, indexPath, row in
            guard let self = self else { return }

            let cellConfiguration: UIContentConfiguration

            let section = self.dataSource.snapshot().sectionIdentifiers[indexPath.section]
            let isCollapsedProvider: () -> Bool = { [weak self] in
                guard let self = self else { return false }
                let snapshot = self.dataSource.snapshot(for: section)
                return snapshot.items.contains(row) ? !snapshot.isExpanded(row) : false
            }

            switch row {
            case .collection(let collection):
                let snapshot = self.dataSource.snapshot(for: section)
                let hasChildren = !snapshot.snapshot(of: row, includingParent: false).items.isEmpty
                var configuration = CollectionCell.ContentConfiguration(collection: collection, hasChildren: hasChildren, accessories: .chevron)
                configuration.isCollapsedProvider = isCollapsedProvider
                configuration.toggleCollapsed = { [weak self, weak cell] in
                    guard let self = self, let cell = cell else { return }
                    self.viewModel.process(action: .toggleCollection(collection.identifier, section))
                }
                cellConfiguration = configuration

            case .library(let library):
                var configuration = CollectionCell.LibraryContentConfiguration(name: library.name, accessories: .chevron)
                configuration.isCollapsedProvider = isCollapsedProvider
                configuration.toggleCollapsed = { [weak self, weak cell] in
                    guard let self = self, let cell = cell else { return }
                    self.viewModel.process(action: .toggleLibrary(section))
                }
                cellConfiguration = configuration
            }

            cell.contentConfiguration = cellConfiguration
            cell.backgroundConfiguration = .listPlainCell()
        }
    }()

    private func createDataSource(for collectionView: UICollectionView) -> UICollectionViewDiffableDataSource<LibraryIdentifier, Row> {
        let registration = self.cellRegistration
        return UICollectionViewDiffableDataSource<LibraryIdentifier, Row>(collectionView: collectionView, cellProvider: { collectionView, indexPath, row in
            return collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: row)
        })
    }

    private func createCollectionViewLayout() -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { _, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.showsSeparators = false
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        }
    }

    // MARK: - Setups

    private func setupSearchController() {
        let resultsController = SearchResultsController()
        resultsController.pickedAction = { [weak self] collection, libraryId in
            self?.picked(collection: collection, libraryId: libraryId)
        }
        let searchController = UISearchController(searchResultsController: resultsController)
        searchController.searchBar.autocapitalizationType = .none
        self.navigationItem.searchController = searchController

        searchController.searchBar.rx.text.observe(on: MainScheduler.instance)
                                  .skip(1)
                                  .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                                  .subscribe(onNext: { [weak self] text in
                                      let term = (text ?? "").isEmpty ? nil : text
                                      self?.viewModel.process(action: .search(term))
                                  })
                                  .disposed(by: self.disposeBag)
    }
}

extension AllCollectionPickerViewController {
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        guard let row = self.dataSource.itemIdentifier(for: indexPath) else { return }

        switch row {
        case .collection(let collection):
            guard indexPath.section < self.viewModel.state.libraries.count else { return }
            let library = self.viewModel.state.libraries[indexPath.section]
            self.picked(collection: collection, library: library)

        case .library(let library):
            self.picked(collection: nil, library: library)
        }
    }
}

private class SearchResultsController: UICollectionViewController {
    fileprivate enum Row: Hashable {
        case library(Library)
        case collection(SearchableCollection)
    }

    fileprivate var dataSource: UICollectionViewDiffableDataSource<LibraryIdentifier, Row>!

    var pickedAction: ((Collection?, LibraryIdentifier) -> Void)?

    init() {
        super.init(collectionViewLayout: UICollectionViewFlowLayout())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.collectionView.collectionViewLayout = self.createCollectionViewLayout()
        self.dataSource = self.createDataSource(for: self.collectionView)
    }

    private lazy var cellRegistration: UICollectionView.CellRegistration<CollectionCell, Row> = {
        return UICollectionView.CellRegistration<CollectionCell, Row> { [weak self] cell, indexPath, row in
            guard let self = self else { return }

            let cellConfiguration: UIContentConfiguration

            switch row {
            case .collection(let searchable):
                let section = self.dataSource.snapshot().sectionIdentifiers[indexPath.section]
                let snapshot = self.dataSource.snapshot(for: section)
                let hasChildren = !snapshot.snapshot(of: row, includingParent: false).items.isEmpty
                cellConfiguration = CollectionCell.SearchContentConfiguration(collection: searchable.collection, hasChildren: hasChildren, isActive: searchable.isActive, accessories: [])

            case .library(let library):
                cellConfiguration = CollectionCell.LibraryContentConfiguration(name: library.name, accessories: [])
            }

            cell.contentConfiguration = cellConfiguration
            cell.backgroundConfiguration = .listPlainCell()
        }
    }()

    private func createDataSource(for collectionView: UICollectionView) -> UICollectionViewDiffableDataSource<LibraryIdentifier, Row> {
        let registration = self.cellRegistration
        return UICollectionViewDiffableDataSource<LibraryIdentifier, Row>(collectionView: collectionView, cellProvider: { collectionView, indexPath, row in
            return collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: row)
        })
    }

    private func createCollectionViewLayout() -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { _, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.showsSeparators = false
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        }
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        guard let row = self.dataSource.itemIdentifier(for: indexPath) else { return }

        let libraryId = self.dataSource.snapshot().sectionIdentifiers[indexPath.section]

        switch row {
        case .collection(let searchable):
            self.pickedAction?(searchable.collection, libraryId)

        case .library:
            self.pickedAction?(nil, libraryId)
        }
    }
}
