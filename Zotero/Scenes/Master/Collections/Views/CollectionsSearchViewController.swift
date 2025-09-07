//
//  CollectionsSearchViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 05/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class CollectionsSearchViewController: UIViewController {
    @IBOutlet private weak var searchBar: UISearchBar!
    @IBOutlet private weak var searchBarSeparatorHeight: NSLayoutConstraint!
    @IBOutlet private weak var collectionView: UICollectionView!

    private let collectionsSection: Int = 0
    private let viewModel: ViewModel<CollectionsSearchActionHandler>
    private let selectAction: (Collection) -> Void
    private let disposeBag: DisposeBag
    private let updateQueue: DispatchQueue

    private var dataSource: UICollectionViewDiffableDataSource<Int, SearchableCollection>!

    init(viewModel: ViewModel<CollectionsSearchActionHandler>, selectAction: @escaping (Collection) -> Void) {
        self.viewModel = viewModel
        self.selectAction = selectAction
        disposeBag = DisposeBag()
        updateQueue = DispatchQueue(label: "org.zotero.CollectionsSearchViewController.UpdateQueue")
        super.init(nibName: "CollectionsSearchViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        searchBarSeparatorHeight.constant = 1 / UIScreen.main.scale
        setupSearchBar()
        setupCollectionView()
        setupKeyboardObserving()
        setupDataSource()

        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(to: state)
            })
            .disposed(by: disposeBag)
    }

    // MARK: - UI state

    private func update(to state: CollectionsSearchState) {
        updateQueue.async { [weak self] in
            self?.dataSource.apply(state.collectionTree.createSearchSnapshot(), to: 0, animatingDifferences: true)
        }
    }

    private lazy var cellRegistration: UICollectionView.CellRegistration<CollectionCell, SearchableCollection> = {
        return UICollectionView.CellRegistration<CollectionCell, SearchableCollection> { [weak self] cell, _, searchable in
            guard let self else { return }

            let snapshot = dataSource.snapshot(for: collectionsSection)
            let hasChildren = !snapshot.snapshot(of: searchable, includingParent: false).items.isEmpty
            let configuration = CollectionCell.SearchContentConfiguration(collection: searchable.collection, hasChildren: hasChildren, isActive: searchable.isActive, accessories: [.badge])

            cell.contentConfiguration = configuration
            cell.backgroundConfiguration = .listPlainCell()
            if #available(iOS 26.0.0, *) {
                cell.indentationWidth = 16
            }
        }
    }()

   // MARK: - Setups

    private func setupSearchBar() {
        searchBar.placeholder = L10n.Collections.searchTitle

        searchBar.rx.text
            .observe(on: MainScheduler.instance)
            .skip(1)
            .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
            .subscribe(onNext: { [weak self] text in
                self?.viewModel.process(action: .search(text ?? ""))
            })
            .disposed(by: disposeBag)

        searchBar.rx.cancelButtonClicked
            .observe(on: MainScheduler.instance)
            .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
            .subscribe(onNext: { [weak self] _ in
                self?.dismiss(animated: true, completion: nil)
            })
            .disposed(by: disposeBag)

        searchBar.becomeFirstResponder()
    }

    private func setupCollectionView() {
        collectionView.delegate = self
        collectionView.collectionViewLayout = UICollectionViewCompositionalLayout { _, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.showsSeparators = false
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        }
    }

    private func setupDataSource() {
        let registration = cellRegistration

        let dataSource = UICollectionViewDiffableDataSource<Int, SearchableCollection>(collectionView: collectionView, cellProvider: { collectionView, indexPath, searchable in
            return collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: searchable)
        })
        self.dataSource = dataSource

        updateQueue.async { [weak self] in
            var snapshot = NSDiffableDataSourceSnapshot<Int, SearchableCollection>()
            snapshot.appendSections([0])
            self?.dataSource.apply(snapshot, animatingDifferences: false)
        }
    }

    private func setupCollectionView(with keyboardData: KeyboardData) {
        var insets = collectionView.contentInset
        insets.bottom = keyboardData.visibleHeight
        collectionView.contentInset = insets
    }

    private func setupKeyboardObserving() {
        NotificationCenter.default
            .keyboardWillShow
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] notification in
                if let data = notification.keyboardData {
                    self?.setupCollectionView(with: data)
                }
            })
            .disposed(by: disposeBag)

        NotificationCenter.default
            .keyboardWillHide
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] notification in
                if let data = notification.keyboardData {
                    self?.setupCollectionView(with: data)
                }
            })
            .disposed(by: disposeBag)
    }
}

extension CollectionsSearchViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let searchable = dataSource.itemIdentifier(for: indexPath), searchable.isActive else {
            collectionView.deselectItem(at: indexPath, animated: false)
            return
        }
        selectAction(searchable.collection)
        dismiss(animated: true, completion: nil)
    }
}
