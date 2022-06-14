//
//  CiteSearchViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 04.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class CiteSearchViewController: UIViewController {
    @IBOutlet private weak var tableView: UITableView!
    @IBOutlet private weak var activityIndicator: UIActivityIndicatorView!

    private let viewModel: ViewModel<CiteSearchActionHandler>
    private let pickAction: (RemoteStyle) -> Void
    private let disposeBag: DisposeBag

    private var dataSource: UITableViewDiffableDataSource<Int, RemoteStyle>!
    weak var coordinatorDelegate: CitationStyleSearchSettingsCoordinatorDelegate?

    init(viewModel: ViewModel<CiteSearchActionHandler>, pickAction: @escaping (RemoteStyle) -> Void) {
        self.viewModel = viewModel
        self.pickAction = pickAction
        self.disposeBag = DisposeBag()
        super.init(nibName: "CiteSearchViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupTableView()
        self.setupSearchController()

        self.viewModel.stateObservable.subscribe(onNext: { [weak self] state in
            self?.update(state: state)
        }).disposed(by: self.disposeBag)

        self.viewModel.process(action: .load)
    }

    // MARK: - Actions

    private func update(state: CiteSearchState) {
        if state.error != nil {
            self.coordinatorDelegate?.showError(retryAction: { [weak self] in
                self?.viewModel.process(action: .load)
            }, cancelAction: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            })
        }

        if state.changes.contains(.loading) {
            self.activityIndicator.isHidden = !state.loading
            self.tableView.isHidden = state.loading

            if state.loading {
                self.activityIndicator.startAnimating()
            } else {
                self.activityIndicator.stopAnimating()
            }
        }

        if state.changes.contains(.styles) {
            let styles = state.filtered ?? state.styles

            var snapshot = NSDiffableDataSourceSnapshot<Int, RemoteStyle>()
            snapshot.appendSections([0])
            snapshot.appendItems(styles, toSection: 0)
            self.dataSource.apply(snapshot)
        }
    }

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.delegate = self
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")

        self.dataSource = UITableViewDiffableDataSource(tableView: self.tableView, cellProvider: { tableView, indexPath, style in
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            cell.textLabel?.text = style.title
            cell.detailTextLabel?.text = Formatter.sqlFormat.string(from: style.updated)
            return cell
        })
    }

    private func setupSearchController() {
        let searchBar = UISearchBar()
        searchBar.placeholder = L10n.Settings.CiteSearch.searchTitle
        searchBar.rx.text.observe(on: MainScheduler.instance)
                         .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                         .subscribe(onNext: { [weak self] text in
                             self?.viewModel.process(action: .search(text ?? ""))
                         })
                         .disposed(by: self.disposeBag)
        self.navigationItem.titleView = searchBar
    }
}

extension CiteSearchViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if let style = self.dataSource.itemIdentifier(for: indexPath) {
            self.pickAction(style)
            self.navigationController?.popViewController(animated: true)
        }
    }
}
