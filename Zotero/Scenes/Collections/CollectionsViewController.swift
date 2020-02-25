//
//  CollectionsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 17/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import UIKit
import SwiftUI

import RealmSwift
import RxSwift

protocol CollectionsNavigationDelegate: class {
    func show(collection: Collection, in library: Library)
}

class CollectionsViewController: UIViewController {
    @IBOutlet private weak var tableView: UITableView!

    private static let cellId = "CollectionRow"
    private let store: ViewModel<CollectionsActionHandler>
    private unowned let dragDropController: DragDropController
    private unowned let dbStorage: DbStorage
    private let disposeBag: DisposeBag

    private var tableViewHandler: CollectionsTableViewHandler!
    private var didAppear: Bool
    private var collectionsToken: NotificationToken?
    private var searchesToken: NotificationToken?
    private var tmpResults: CollectionsResults?
    weak var navigationDelegate: CollectionsNavigationDelegate?

    init(results: CollectionsResults?, viewModel: ViewModel<CollectionsActionHandler>, dbStorage: DbStorage, dragDropController: DragDropController) {
        self.store = viewModel
        self.dbStorage = dbStorage
        self.dragDropController = dragDropController
        self.disposeBag = DisposeBag()
        self.didAppear = false
        self.tmpResults = results

        super.init(nibName: "CollectionsViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = self.store.state.library.name
        self.setupNavbarItems()
        self.tableViewHandler = CollectionsTableViewHandler(tableView: self.tableView,
                                                            viewModel: self.store,
                                                            dragDropController: self.dragDropController)
        self.tableViewHandler.update(collections: self.store.state.collections, animated: false)

        if let results = self.tmpResults {
            self.setupObserving(for: results)
            self.tmpResults = nil
        }

        self.store.stateObservable
                  .observeOn(MainScheduler.instance)
                  .subscribe(onNext: { [weak self] state in
                      self?.update(to: state)
                  })
                  .disposed(by: self.disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if UIDevice.current.userInterfaceIdiom == .pad {
            self.navigationDelegate?.show(collection: self.store.state.selectedCollection, in: self.store.state.library)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.didAppear = true
    }

    // MARK: - UI state

    private func update(to state: CollectionsState) {
        if state.changes.contains(.results) {
            self.tableViewHandler.update(collections: state.collections, animated: true)
        }
        if state.changes.contains(.selection) {
            self.navigationDelegate?.show(collection: state.selectedCollection, in: state.library)
        }
        if let data = state.editingData {
            self.presentEditView(for: data)
        }
    }

    // MARK: - Navigation

    @objc private func addCollection() {
        self.store.process(action: .startEditing(.add))
    }

    private func presentEditView(for data: CollectionStateEditingData) {
        let view = NavigationView {
            self.createEditView(for: data)
        }
        .navigationViewStyle(StackNavigationViewStyle())

        let controller = UIHostingController(rootView: view)
        controller.isModalInPresentation = true
        self.present(controller, animated: true, completion: nil)
    }

    private func createEditView(for data: CollectionStateEditingData) -> some View {
        let store = CollectionEditStore(library: self.store.state.library, key: data.0, name: data.1,
                                        parent: data.2, dbStorage: self.dbStorage)
        store.shouldDismiss = { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        }

        return CollectionEditView(closeAction: { [weak self] in self?.dismiss(animated: true, completion: nil) })
                    .environment(\.dbStorage, self.dbStorage)
                    .environmentObject(store)
    }

    // MARK: - Setups

    private func setupNavbarItems() {
        let item = UIBarButtonItem(image: UIImage(systemName: "plus"),
                                   style: .plain,
                                   target: self,
                                   action: #selector(CollectionsViewController.addCollection))
        self.navigationItem.rightBarButtonItem = item
    }

    private func setupObserving(for results: CollectionsResults) {
        self.collectionsToken = results.1.observe({ [weak self] changes in
            guard let `self` = self else { return }
            switch changes {
            case .update(let objects, _, _, _):
                self.store.process(action: .updateCollections(CollectionTreeBuilder.collections(from: objects)))
            case .initial: break
            case .error: break
            }
        })
        self.searchesToken = results.2.observe({ [weak self] changes in
            guard let `self` = self else { return }
            switch changes {
            case .update(let objects, _, _, _):
                self.store.process(action: .updateCollections(CollectionTreeBuilder.collections(from: objects)))
            case .initial: break
            case .error: break
            }
        })
    }
}
