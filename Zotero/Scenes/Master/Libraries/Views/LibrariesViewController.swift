//
//  LibrariesViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 10/09/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

import RxSwift

final class LibrariesViewController: UIViewController {
    private weak var tableView: UITableView!

    private static let cellId = "LibraryCell"
    private static let customLibrariesSection = 0
    private static let groupLibrariesSection = 1
    private let viewModel: ViewModel<LibrariesActionHandler>
    private unowned let syncScheduler: SynchronizationScheduler
    private let disposeBag: DisposeBag

    private var refreshController: SyncRefreshController?
    weak var coordinatorDelegate: MasterLibrariesCoordinatorDelegate?
    private var isSplit: Bool {
        splitViewController?.isCollapsed == false
    }

    // MARK: - Lifecycle

    init(viewModel: ViewModel<LibrariesActionHandler>, syncScheduler: SynchronizationScheduler) {
        self.viewModel = viewModel
        self.syncScheduler = syncScheduler
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupNavigationBar()
        setupTableView()
        viewModel.process(action: .loadData)
        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(to: state)
            })
            .disposed(by: disposeBag)

        func setupNavigationBar() {
            let item = UIBarButtonItem(image: UIImage(systemName: "gear"))
            item.tintColor = Asset.Colors.zoteroBlue.color
            item.accessibilityLabel = L10n.Settings.title
            item.primaryAction = UIAction(handler: { [weak self] action in
                self?.coordinatorDelegate?.showSettings(sourceItem: action.sender as? UIPopoverPresentationControllerSourceItem)
            })
            navigationItem.rightBarButtonItem = item
        }

        func setupTableView() {
            let tableView: UITableView
            tableView = UITableView(frame: .zero, style: .grouped)
            tableView.rowHeight = 44
            tableView.separatorInset = UIEdgeInsets(top: 0, left: 60, bottom: 0, right: 0)
            tableView.dataSource = self
            tableView.delegate = self
            tableView.register(LibraryCell.self, forCellReuseIdentifier: Self.cellId)
            tableView.tableFooterView = UIView()
            tableView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(tableView)
            self.tableView = tableView

            NSLayoutConstraint.activate([
                tableView.topAnchor.constraint(equalTo: view.topAnchor),
                tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
            ])
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        if !isSplit {
            guard tableView.refreshControl == nil else { return }
            refreshController = SyncRefreshController(libraryId: nil, view: tableView, syncScheduler: syncScheduler)
        } else {
            refreshController = nil
        }
    }

    // MARK: - UI State

    private func update(to state: LibrariesState) {
        if state.changes.contains(.groups) {
            tableView.reloadData()
        }

        if state.changes.contains(.groupDeletion) {
            showDefaultLibraryIfNeeded(for: state)
        }

        if let error = state.error {
            coordinatorDelegate?.show(error: error)
        }

        if let question = state.deleteGroupQuestion {
            coordinatorDelegate?.showDeleteGroupQuestion(id: question.id, name: question.name, viewModel: viewModel)
        }
    }

    // MARK: - Actions

    private func showDefaultLibraryIfNeeded(for state: LibrariesState) {
        switch coordinatorDelegate?.visibleLibraryId {
        case .none, .custom:
            break

        case .group(let groupId):
            if state.groupLibraries?.filter(.groupId(groupId)).first == nil {
                // Currently visible group was recently deleted, show default library
                coordinatorDelegate?.showDefaultLibrary()
            }
        }
    }
}

extension LibrariesViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        let groupCount = viewModel.state.groupLibraries?.count ?? 0
        return groupCount > 0 ? 2 : 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case Self.customLibrariesSection:
            return viewModel.state.customLibraries?.count ?? 0

        case Self.groupLibrariesSection:
            return viewModel.state.groupLibraries?.count ?? 0

        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == Self.groupLibrariesSection ? L10n.Libraries.groupLibraries : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellId, for: indexPath)
        if let cell = cell as? LibraryCell, let (name, state) = libraryData(for: indexPath) {
            cell.setup(with: name, libraryState: state)
        }
        return cell

        func libraryData(for indexPath: IndexPath) -> (name: String, state: LibraryCell.LibraryState)? {
            switch indexPath.section {
            case Self.customLibrariesSection:
                let library = viewModel.state.customLibraries?[indexPath.row]
                return library.flatMap({ ($0.type.libraryName, .normal) })

            case Self.groupLibrariesSection:
                guard let library = viewModel.state.groupLibraries?[indexPath.row] else { return nil }
                let state: LibraryCell.LibraryState
                if library.isLocalOnly {
                    state = .archived
                } else if !library.canEditMetadata {
                    state = .locked
                } else {
                    state = .normal
                }
                return (library.name, state)

            default:
                return nil
            }
        }
    }
}

extension LibrariesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let library = library(for: indexPath) {
            coordinatorDelegate?.showCollections(for: library.identifier)
        }

        func library(for indexPath: IndexPath) -> Library? {
            switch indexPath.section {
            case Self.customLibrariesSection:
                let library = viewModel.state.customLibraries?[indexPath.row]
                return library.flatMap({ Library(customLibrary: $0) })

            case Self.groupLibrariesSection:
                let library = viewModel.state.groupLibraries?[indexPath.row]
                return library.flatMap({ Library(group: $0) })

            default:
                return nil
            }
        }
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPath.section == Self.groupLibrariesSection, let group = viewModel.state.groupLibraries?[indexPath.row], group.isLocalOnly else { return nil }

        let groupId = group.identifier
        let groupName = group.name

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ -> UIMenu? in
            return createContextMenu(for: groupId, groupName: groupName)
        }

        func createContextMenu(for groupId: Int, groupName: String) -> UIMenu {
            let delete = UIAction(title: L10n.remove, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.viewModel.process(action: .showDeleteGroupQuestion((groupId, groupName)))
            }
            return UIMenu(title: "", children: [delete])
        }
    }
}

extension LibrariesViewController: BottomSheetObserver { }

extension LibrariesViewController: WebViewProvider {
    func addWebView(configuration: WKWebViewConfiguration?) -> WKWebView {
        let webView: WKWebView = configuration.flatMap({ WKWebView(frame: .zero, configuration: $0) }) ?? WKWebView()
        webView.isHidden = true
        view.insertSubview(webView, at: 0)
        return webView
    }
}
