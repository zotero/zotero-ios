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
    @IBOutlet private weak var tableView: UITableView!

    private static let cellId = "CollectionRow"
    private let viewModel: ViewModel<CollectionsSearchActionHandler>
    private let selectAction: (Collection) -> Void
    private let disposeBag: DisposeBag

    private var dataSource: UITableViewDiffableDataSource<Int, SearchableCollection>!

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
        self.setupTableView()
        self.setupKeyboardObserving()
        self.setupDataSource()

        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .skip(1)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(to: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    // MARK: - UI state

    private func update(to state: CollectionsSearchState) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, SearchableCollection>()
        snapshot.appendSections([0])
        snapshot.appendItems(state.filtered, toSection: 0)
        self.dataSource.apply(snapshot, animatingDifferences: true, completion: nil)
    }

   // MARK: - Setups

    private func setupSearchBar() {
        self.searchBar.placeholder = L10n.Collections.searchTitle

        self.searchBar.rx.text
                         .observe(on: MainScheduler.instance)
                         .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                         .subscribe(onNext: { [weak self] text in
                            self?.viewModel.process(action: .search(text ?? ""))
                         })
                         .disposed(by: self.disposeBag)

        self.searchBar.rx.cancelButtonClicked
                         .observe(on: MainScheduler.instance)
                         .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                         .subscribe(onNext: { [weak self] text in
                             self?.dismiss(animated: true, completion: nil)
                         })
                         .disposed(by: self.disposeBag)

        self.searchBar.becomeFirstResponder()
    }

    private func setupTableView() {
        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.tableView.delegate = self
        self.tableView.rowHeight = 44
        self.tableView.register(UINib(nibName: "CollectionCell", bundle: nil), forCellReuseIdentifier: CollectionsSearchViewController.cellId)
    }

    private func setupDataSource() {
        self.dataSource = UITableViewDiffableDataSource(tableView: self.tableView,
                                                        cellProvider: { tableView, indexPath, object -> UITableViewCell? in
            let cell = tableView.dequeueReusableCell(withIdentifier: CollectionsSearchViewController.cellId, for: indexPath) as? CollectionCell
            cell?.set(searchableCollection: object)
            return cell
        })
    }

    private func setupTableView(with keyboardData: KeyboardData) {
        var insets = self.tableView.contentInset
        insets.bottom = keyboardData.endFrame.height
        self.tableView.contentInset = insets
    }

    private func setupKeyboardObserving() {
        NotificationCenter.default
                          .keyboardWillShow
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.setupTableView(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)

        NotificationCenter.default
                          .keyboardWillHide
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.setupTableView(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)
    }

}

extension CollectionsSearchViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let collection = self.dataSource.itemIdentifier(for: indexPath)?.collection else { return }
        self.selectAction(collection)
        self.dismiss(animated: true, completion: nil)
    }
}
