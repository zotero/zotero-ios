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

    private var dataSource: UICollectionViewDiffableDataSource<Int, Collection>!
    private var addButton: UIBarButtonItem?

    init(mode: Mode, viewModel: ViewModel<CollectionsPickerActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()

        switch mode {
        case .single(let title, let selected):
            self.multipleSelectionAllowed = false
            self.titleType = .fixed(title)
            self.collectionSelected = selected
            self.keysSelected = nil

        case .multiple(let selected):
            self.multipleSelectionAllowed = true
            self.titleType = .dynamic
            self.keysSelected = selected
            self.collectionSelected = nil
        }

        super.init(collectionViewLayout: UICollectionViewFlowLayout())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupCollectionView()
        self.setupDataSource()
        self.setupNavigationBar()

        switch self.titleType {
        case .fixed(let title):
            self.title = title
        case .dynamic:
            self.updateTitle(with: self.viewModel.state.selected.count)
        }

        self.viewModel.process(action: .loadData)
        self.updateDataSource(with: self.viewModel.state, animated: false)

        self.viewModel.stateObservable
                      .skip(1)
                      .observe(on: MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(to: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    // MARK: - Actions

    private func confirmSelection() {
        guard let action = self.keysSelected else { return }
        action(self.viewModel.state.selected)
        self.close()
    }

    private func close() {
        if self.multipleSelectionAllowed {
            self.presentingViewController?.dismiss(animated: true, completion: nil)
        } else {
            self.navigationController?.popViewController(animated: true)
        }
    }

    // MARK: - UI state

    private func update(to state: CollectionsPickerState) {
        if state.changes.contains(.results) {
            self.updateDataSource(with: state, animated: true)
        }

        if state.changes.contains(.selection) && self.titleType.isDynamic {
            self.updateTitle(with: state.selected.count)
        }

        if let error = state.error {
            // TODO: - show error
        }
    }

    private func updateTitle(with selectedCount: Int) {
        switch selectedCount {
        case 0:
            self.title = L10n.Items.zeroCollectionsSelected
        case 1:
            self.title = L10n.Items.oneCollectionsSelected
        default:
            self.title = L10n.Items.manyCollectionsSelected(selectedCount)
        }
    }

    private func updateDataSource(with state: CollectionsPickerState, animated: Bool) {
        self.dataSource.apply(state.collectionTree.createSnapshot(collapseState: .expandedAll), to: 0, animatingDifferences: animated) { [weak self] in
            guard let self = self, self.multipleSelectionAllowed else { return }
            self.select(selected: state.selected, tree: state.collectionTree)
        }
    }

    private func select(selected: Set<String>, tree: CollectionTree) {
        // Deselect everything
        for indexPath in self.collectionView.indexPathsForSelectedItems ?? [] {
            self.collectionView.deselectItem(at: indexPath, animated: false)
        }

        // Select selected collections
        let indexPaths = selected.compactMap({ self.viewModel.state.collectionTree.collection(for: .collection($0)) }).compactMap({ self.dataSource.indexPath(for: $0) })
        for indexPath in indexPaths {
            self.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        }
    }

    private lazy var cellRegistration: UICollectionView.CellRegistration<CollectionCell, Collection> = {
        return UICollectionView.CellRegistration<CollectionCell, Collection> { [weak self] cell, _, collection in
            guard let self = self else { return }

            let snapshot = self.dataSource.snapshot(for: self.collectionsSection)
            let hasChildren = !snapshot.snapshot(of: collection, includingParent: false).items.isEmpty
            let configuration = CollectionCell.ContentConfiguration(collection: collection, hasChildren: hasChildren, accessories: [])

            cell.contentConfiguration = configuration
            cell.backgroundConfiguration = .listPlainCell()

            if self.multipleSelectionAllowed {
                cell.accessories = [.multiselect()]
            } else {
                if let key = collection.identifier.key, self.viewModel.state.selected.contains(key) {
                    cell.accessories = [.checkmark()]
                } else {
                    cell.accessories = []
                }
            }
        }
    }()

   // MARK: - Setups

    private func setupCollectionView() {
        self.collectionView.delegate = self
        self.collectionView.allowsMultipleSelectionDuringEditing = true
        self.collectionView.isEditing = self.multipleSelectionAllowed

        self.collectionView.collectionViewLayout = UICollectionViewCompositionalLayout { _, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.showsSeparators = false
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        }
    }

    private func setupDataSource() {
        let registration = self.cellRegistration

        let dataSource = UICollectionViewDiffableDataSource<Int, Collection>(collectionView: collectionView, cellProvider: { collectionView, indexPath, collection in
            return collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: collection)
        })
        self.dataSource = dataSource

        var snapshot = NSDiffableDataSourceSnapshot<Int, Collection>()
        snapshot.appendSections([0])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func setupNavigationBar() {
        guard self.multipleSelectionAllowed else { return }

        let cancel = UIBarButtonItem(barButtonSystemItem: .cancel, target: nil, action: nil)
        cancel.rx.tap.subscribe(onNext: { [weak self] in
            self?.close()
        }).disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = cancel

        let add = UIBarButtonItem(title: L10n.add, style: .plain, target: nil, action: nil)
        add.rx.tap.subscribe(onNext: { [weak self] in
            self?.confirmSelection()
        }).disposed(by: self.disposeBag)
        self.addButton = add
        self.navigationItem.rightBarButtonItem = add
    }
}

extension CollectionsPickerViewController {
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let collection = self.dataSource.itemIdentifier(for: indexPath) else {
            collectionView.deselectItem(at: indexPath, animated: false)
            return
        }

        if self.multipleSelectionAllowed {
            self.viewModel.process(action: .select(collection))
        } else if let action = self.collectionSelected {
            action(collection)
            self.close()
        }
    }

    override func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard let collection = self.dataSource.itemIdentifier(for: indexPath) else {
            collectionView.deselectItem(at: indexPath, animated: false)
            return
        }

        if self.multipleSelectionAllowed {
            self.viewModel.process(action: .deselect(collection))
        }
    }
}
