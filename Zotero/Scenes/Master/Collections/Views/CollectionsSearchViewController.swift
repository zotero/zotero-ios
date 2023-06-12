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

    private var dataSource: UICollectionViewDiffableDataSource<Int, SearchableCollection>!

    init(viewModel: ViewModel<CollectionsSearchActionHandler>, selectAction: @escaping (Collection) -> Void) {
        self.viewModel = viewModel
        self.selectAction = selectAction
        self.disposeBag = DisposeBag()
        super.init(nibName: "CollectionsSearchViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.searchBarSeparatorHeight.constant = 1 / UIScreen.main.scale
        self.setupSearchBar()
        self.setupCollectionView()
        self.setupKeyboardObserving()
        self.setupDataSource()

        self.viewModel.stateObservable
                      .skip(1)
                      .observe(on: MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(to: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    // MARK: - UI state

    private func update(to state: CollectionsSearchState) {
        self.dataSource.apply(state.collectionTree.createSearchSnapshot(), to: 0, animatingDifferences: true)
    }

    private lazy var cellRegistration: UICollectionView.CellRegistration<CollectionCell, SearchableCollection> = {
        return UICollectionView.CellRegistration<CollectionCell, SearchableCollection> { [weak self] cell, _, searchable in
            guard let self = self else { return }

            let snapshot = self.dataSource.snapshot(for: self.collectionsSection)
            let hasChildren = !snapshot.snapshot(of: searchable, includingParent: false).items.isEmpty
            let configuration = CollectionCell.SearchContentConfiguration(collection: searchable.collection, hasChildren: hasChildren, isActive: searchable.isActive, accessories: [.badge])

            cell.contentConfiguration = configuration
            cell.backgroundConfiguration = .listPlainCell()
        }
    }()

   // MARK: - Setups

    private func setupSearchBar() {
        self.searchBar.placeholder = L10n.Collections.searchTitle

        self.searchBar.rx.text
                         .observe(on: MainScheduler.instance)
                         .skip(1)
                         .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                         .subscribe(onNext: { [weak self] text in
                            self?.viewModel.process(action: .search(text ?? ""))
                         })
                         .disposed(by: self.disposeBag)

        self.searchBar.rx.cancelButtonClicked
                         .observe(on: MainScheduler.instance)
                         .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                         .subscribe(onNext: { [weak self] _ in
                             self?.dismiss(animated: true, completion: nil)
                         })
                         .disposed(by: self.disposeBag)

        self.searchBar.becomeFirstResponder()
    }

    private func setupCollectionView() {
        self.collectionView.delegate = self
        self.collectionView.collectionViewLayout = UICollectionViewCompositionalLayout { _, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.showsSeparators = false
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        }
    }

    private func setupDataSource() {
        let registration = self.cellRegistration

        let dataSource = UICollectionViewDiffableDataSource<Int, SearchableCollection>(collectionView: collectionView, cellProvider: { collectionView, indexPath, searchable in
            return collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: searchable)
        })
        self.dataSource = dataSource

        var snapshot = NSDiffableDataSourceSnapshot<Int, SearchableCollection>()
        snapshot.appendSections([0])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func setupCollectionView(with keyboardData: KeyboardData) {
        var insets = self.collectionView.contentInset
        insets.bottom = keyboardData.visibleHeight
        self.collectionView.contentInset = insets
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
                          .disposed(by: self.disposeBag)

        NotificationCenter.default
                          .keyboardWillHide
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.setupCollectionView(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)
    }

}

extension CollectionsSearchViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let searchable = self.dataSource.itemIdentifier(for: indexPath), searchable.isActive else {
            collectionView.deselectItem(at: indexPath, animated: false)
            return
        }
        self.selectAction(searchable.collection)
        self.dismiss(animated: true, completion: nil)
    }
}
