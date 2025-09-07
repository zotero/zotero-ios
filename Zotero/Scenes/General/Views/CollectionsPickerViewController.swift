//
//  CollectionsPickerViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 10.02.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class CollectionsPickerViewController: UICollectionViewController {
    enum Mode {
        case single(title: String, selected: (Collection) -> Void)
        case multiple(selected: (Set<String>) -> Void)
    }

    private enum TitleType {
        case fixed(String)
        case dynamic

        var isDynamic: Bool {
            switch self {
            case .dynamic: return true
            case .fixed: return false
            }
        }
    }

    private let collectionsSection: Int = 0
    private let viewModel: ViewModel<CollectionsPickerActionHandler>
    private let disposeBag: DisposeBag
    private let titleType: TitleType
    private let collectionSelected: ((Collection) -> Void)?
    private let keysSelected: ((Set<String>) -> Void)?
    private let multipleSelectionAllowed: Bool
    private let updateQueue: DispatchQueue

    private var dataSource: UICollectionViewDiffableDataSource<Int, Collection>!
    private var addButton: UIBarButtonItem?

    init(mode: Mode, viewModel: ViewModel<CollectionsPickerActionHandler>) {
        self.viewModel = viewModel
        disposeBag = DisposeBag()
        updateQueue = DispatchQueue(label: "org.zotero.CollectionsPickerViewController.UpdateQueue")

        switch mode {
        case .single(let title, let selected):
            multipleSelectionAllowed = false
            titleType = .fixed(title)
            collectionSelected = selected
            keysSelected = nil

        case .multiple(let selected):
            multipleSelectionAllowed = true
            titleType = .dynamic
            keysSelected = selected
            collectionSelected = nil
        }

        super.init(collectionViewLayout: UICollectionViewFlowLayout())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupCollectionView()
        setupDataSource()
        setupNavigationBar()

        switch titleType {
        case .fixed(let title):
            self.title = title

        case .dynamic:
            updateTitle(with: viewModel.state.selected.count)
        }

        viewModel.process(action: .loadData)
        updateDataSource(with: viewModel.state, animated: false)

        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(to: state)
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Actions

    private func confirmSelection() {
        guard let keysSelected else { return }
        keysSelected(viewModel.state.selected)
        close()
    }

    private func close() {
        if multipleSelectionAllowed {
            presentingViewController?.dismiss(animated: true, completion: nil)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    // MARK: - UI state

    private func update(to state: CollectionsPickerState) {
        if state.changes.contains(.results) {
            updateDataSource(with: state, animated: true)
        }

        if state.changes.contains(.selection) && titleType.isDynamic {
            updateTitle(with: state.selected.count)
        }

        if let error = state.error {
            // TODO: - show error
        }
    }

    private func updateTitle(with selectedCount: Int) {
        title = L10n.Items.collectionsSelected(selectedCount)
    }

    private func updateDataSource(with state: CollectionsPickerState, animated: Bool) {
        updateQueue.async { [weak self] in
            guard let self else { return }
            dataSource.apply(state.collectionTree.createSnapshot(collapseState: .expandedAll), to: 0, animatingDifferences: animated) { [weak self] in
                guard let self, multipleSelectionAllowed else { return }
                select(selected: state.selected, tree: state.collectionTree)
            }
        }
    }

    private func select(selected: Set<String>, tree: CollectionTree) {
        // Deselect everything
        for indexPath in collectionView.indexPathsForSelectedItems ?? [] {
            collectionView.deselectItem(at: indexPath, animated: false)
        }

        // Select selected collections
        let indexPaths = selected.compactMap({ viewModel.state.collectionTree.collection(for: .collection($0)) }).compactMap({ dataSource.indexPath(for: $0) })
        for indexPath in indexPaths {
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        }
    }

    private lazy var cellRegistration: UICollectionView.CellRegistration<CollectionCell, Collection> = {
        return UICollectionView.CellRegistration<CollectionCell, Collection> { [weak self] cell, _, collection in
            guard let self else { return }

            let snapshot = dataSource.snapshot(for: collectionsSection)
            let hasChildren = !snapshot.snapshot(of: collection, includingParent: false).items.isEmpty
            let configuration = CollectionCell.ContentConfiguration(collection: collection, hasChildren: hasChildren, accessories: [])

            cell.contentConfiguration = configuration
            cell.backgroundConfiguration = .listPlainCell()
            if #available(iOS 26.0.0, *) {
                cell.indentationWidth = 16
            }

            if multipleSelectionAllowed {
                cell.accessories = [.multiselect()]
            } else {
                if let key = collection.identifier.key, viewModel.state.selected.contains(key) {
                    cell.accessories = [.checkmark()]
                } else {
                    cell.accessories = []
                }
            }
        }
    }()

   // MARK: - Setups

    private func setupCollectionView() {
        collectionView.delegate = self
        collectionView.allowsMultipleSelectionDuringEditing = true
        collectionView.isEditing = multipleSelectionAllowed

        collectionView.collectionViewLayout = UICollectionViewCompositionalLayout { _, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.showsSeparators = false
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        }
    }

    private func setupDataSource() {
        let registration = cellRegistration

        let dataSource = UICollectionViewDiffableDataSource<Int, Collection>(collectionView: collectionView, cellProvider: { collectionView, indexPath, collection in
            return collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: collection)
        })
        self.dataSource = dataSource

        updateQueue.async { [weak self] in
            var snapshot = NSDiffableDataSourceSnapshot<Int, Collection>()
            snapshot.appendSections([0])
            self?.dataSource.apply(snapshot, animatingDifferences: false)
        }
    }

    private func setupNavigationBar() {
        guard multipleSelectionAllowed else { return }

        let cancelPrimaryAction = UIAction { [weak self] _ in
            self?.close()
        }
        let cancel = UIBarButtonItem(systemItem: .cancel, primaryAction: cancelPrimaryAction)
        navigationItem.leftBarButtonItem = cancel

        let addPrimaryAction = UIAction(title: L10n.add) { [weak self] _ in
            self?.confirmSelection()
        }
        let add: UIBarButtonItem
        if #available(iOS 26.0.0, *) {
            add = UIBarButtonItem(systemItem: .add, primaryAction: addPrimaryAction)
        } else {
            add = UIBarButtonItem(primaryAction: addPrimaryAction)
        }
        addButton = add
        navigationItem.rightBarButtonItem = add
    }
}

extension CollectionsPickerViewController {
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let collection = dataSource.itemIdentifier(for: indexPath) else {
            collectionView.deselectItem(at: indexPath, animated: false)
            return
        }

        if multipleSelectionAllowed {
            viewModel.process(action: .select(collection))
        } else if let collectionSelected {
            collectionSelected(collection)
            close()
        }
    }

    override func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard let collection = dataSource.itemIdentifier(for: indexPath) else {
            collectionView.deselectItem(at: indexPath, animated: false)
            return
        }

        if multipleSelectionAllowed {
            viewModel.process(action: .deselect(collection))
        }
    }
}
