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
    @IBOutlet private weak var tableView: UITableView!

    private static let cellId = "LibraryCell"
    private static let customLibrariesSection = 0
    private static let groupLibrariesSection = 1
    private let viewModel: ViewModel<LibrariesActionHandler>
    private unowned let identifierLookupController: IdentifierLookupController
    private let disposeBag: DisposeBag

    weak var coordinatorDelegate: MasterLibrariesCoordinatorDelegate?

    // MARK: - Lifecycle

    init(viewModel: ViewModel<LibrariesActionHandler>, identifierLookupController: IdentifierLookupController) {
        self.viewModel = viewModel
        self.identifierLookupController = identifierLookupController
        self.disposeBag = DisposeBag()
        super.init(nibName: "LibrariesViewController", bundle: nil)
        
        identifierLookupController.webViewProvider = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupNavigationBar()
        self.setupTableView()

        self.viewModel.process(action: .loadData)

        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(to: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    // MARK: - UI State

    private func update(to state: LibrariesState) {
        if state.changes.contains(.groups) {
            self.tableView.reloadData()
        }

        if state.changes.contains(.groupDeletion) {
            self.showDefaultLibraryIfNeeded(for: state)
        }

        if let error = state.error {
            self.coordinatorDelegate?.show(error: error)
        }

        if let question = state.deleteGroupQuestion {
            self.coordinatorDelegate?.showDeleteGroupQuestion(id: question.id, name: question.name, viewModel: self.viewModel)
        }
    }

    // MARK: - Actions

    private func showDefaultLibraryIfNeeded(for state: LibrariesState) {
        guard let visibleLibraryId = self.coordinatorDelegate?.visibleLibraryId else { return }
        switch visibleLibraryId {
        case .custom: break

        case .group(let groupId):
            if state.groupLibraries?.filter(.groupId(groupId)).first == nil {
                // Currently visible group was recently deleted, show default library
                self.coordinatorDelegate?.showDefaultLibrary()
            }
        }
    }

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.rowHeight = 44
        self.tableView.separatorInset = UIEdgeInsets(top: 0, left: 60, bottom: 0, right: 0)
        self.tableView.register(UINib(nibName: "LibraryCell", bundle: nil), forCellReuseIdentifier: LibrariesViewController.cellId)
        self.tableView.tableFooterView = UIView()
    }

    private func setupNavigationBar() {
        let item = UIBarButtonItem(image: UIImage(systemName: "gear"), style: .plain, target: nil, action: nil)
        item.accessibilityLabel = L10n.Settings.title
        item.rx.tap
            .subscribe(onNext: { [weak self] _ in
                self?.coordinatorDelegate?.showSettings()
            })
            .disposed(by: self.disposeBag)
        self.navigationItem.rightBarButtonItem = item
    }
}

extension LibrariesViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        let groupCount = self.viewModel.state.groupLibraries?.count ?? 0
        return groupCount > 0 ? 2 : 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case LibrariesViewController.customLibrariesSection:
            return self.viewModel.state.customLibraries?.count ?? 0

        case LibrariesViewController.groupLibrariesSection:
            return self.viewModel.state.groupLibraries?.count ?? 0

        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == LibrariesViewController.groupLibrariesSection ? L10n.Libraries.groupLibraries : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: LibrariesViewController.cellId, for: indexPath)

        if let cell = cell as? LibraryCell,
           let (name, state) = self.libraryData(for: indexPath) {
            cell.setup(with: name, libraryState: state)
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if let library = self.library(for: indexPath) {
            self.coordinatorDelegate?.showCollections(for: library.identifier)
        }
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPath.section == LibrariesViewController.groupLibrariesSection,
              let group = self.viewModel.state.groupLibraries?[indexPath.row],
              group.isLocalOnly else { return nil }

        let groupId = group.identifier
        let groupName = group.name

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ -> UIMenu? in
            return self.createContextMenu(for: groupId, groupName: groupName)
        }
    }

    private func createContextMenu(for groupId: Int, groupName: String) -> UIMenu {
        let delete = UIAction(title: L10n.delete, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            self?.viewModel.process(action: .showDeleteGroupQuestion((groupId, groupName)))
        }
        return UIMenu(title: "", children: [delete])
    }

    private func libraryData(for indexPath: IndexPath) -> (name: String, state: LibraryCell.LibraryState)? {
        switch indexPath.section {
        case LibrariesViewController.customLibrariesSection:
            let library = self.viewModel.state.customLibraries?[indexPath.row]
            return library.flatMap({ ($0.type.libraryName, .normal) })

        case LibrariesViewController.groupLibrariesSection:
            guard let library = self.viewModel.state.groupLibraries?[indexPath.row] else { return nil }
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

    private func library(for indexPath: IndexPath) -> Library? {
        switch indexPath.section {
        case LibrariesViewController.customLibrariesSection:
            let library = self.viewModel.state.customLibraries?[indexPath.row]
            return library.flatMap({ Library(customLibrary: $0) })

        case LibrariesViewController.groupLibrariesSection:
            let library = self.viewModel.state.groupLibraries?[indexPath.row]
            return library.flatMap({ Library(group: $0) })

        default:
            return nil
        }
    }
}

extension LibrariesViewController: BottomSheetObserver { }

extension LibrariesViewController: IdentifierLookupWebViewProvider {
    func addWebView() -> WKWebView {
        let webView = WKWebView()
        webView.isHidden = true
        view.insertSubview(webView, at: 0)
        return webView
    }
    
    func removeWebView(_ webView: WKWebView) {
        if view.subviews.contains(where: { $0 == webView }) {
            webView.removeFromSuperview()
        }
    }
}
