//
//  CitationStyleSearchViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 04.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class CitationStyleSearchViewController: UIViewController {
    @IBOutlet private weak var tableView: UITableView!
    @IBOutlet private weak var activityIndicator: UIActivityIndicatorView!

    private let viewModel: ViewModel<CitationStylesSearchActionHandler>
    private let pickAction: (RemoteCitationStyle) -> Void
    private let disposeBag: DisposeBag

    private var dataSource: DiffableDataSource<Int, RemoteCitationStyle>!
    weak var coordinatorDelegate: CitationStyleSearchSettingsCoordinatorDelegate?

    init(viewModel: ViewModel<CitationStylesSearchActionHandler>, pickAction: @escaping (RemoteCitationStyle) -> Void) {
        self.viewModel = viewModel
        self.pickAction = pickAction
        self.disposeBag = DisposeBag()
        super.init(nibName: "CitationStyleSearchViewController", bundle: nil)
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

    private func update(state: CitationStylesSearchState) {
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
            var snapshot = DiffableDataSourceSnapshot<Int, RemoteCitationStyle>(isEditing: false)
            snapshot.append(section: 0)
            snapshot.append(objects: styles, for: 0)
            let animation: DiffableDataSourceAnimation = state.changes.contains(.loading) ? .none : .rows(reload: .automatic, insert: .automatic, delete: .automatic)
            self.dataSource.apply(snapshot: snapshot, animation: animation, completion: nil)
        }
    }

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.delegate = self
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        self.dataSource = DiffableDataSource(tableView: self.tableView, dequeueAction: { tableView, indexPath, _, _ in
            return tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        }, setupAction: { cell, _, _, style in
            cell.textLabel?.text = style.title
            cell.detailTextLabel?.text = Formatter.sqlFormat.string(from: style.updated)
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

extension CitationStyleSearchViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if let style = self.dataSource.snapshot.object(at: indexPath) {
            self.pickAction(style)
            self.navigationController?.popViewController(animated: true)
        }
    }
}
