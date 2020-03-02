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
    private let viewModel: ViewModel<CollectionsActionHandler>
    private unowned let dragDropController: DragDropController
    private unowned let dbStorage: DbStorage
    private let disposeBag: DisposeBag

    private var tableViewHandler: CollectionsTableViewHandler!
    weak var navigationDelegate: CollectionsNavigationDelegate?

    var collectionsChanged: (([Collection]) -> Void)?

    init(viewModel: ViewModel<CollectionsActionHandler>, dbStorage: DbStorage, dragDropController: DragDropController) {
        self.viewModel = viewModel
        self.dbStorage = dbStorage
        self.dragDropController = dragDropController
        self.disposeBag = DisposeBag()

        super.init(nibName: "CollectionsViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = self.viewModel.state.library.name
        self.setupNavbarItems()
        self.tableViewHandler = CollectionsTableViewHandler(tableView: self.tableView,
                                                            viewModel: self.viewModel,
                                                            dragDropController: self.dragDropController)

        self.viewModel.process(action: .loadData)
        self.tableViewHandler.update(collections: self.viewModel.state.collections, animated: false)
        self.collectionsChanged?(self.viewModel.state.collections)

        self.viewModel.stateObservable
                      .observeOn(MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(to: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if UIDevice.current.userInterfaceIdiom == .pad {
            self.navigationDelegate?.show(collection: self.viewModel.state.selectedCollection, in: self.viewModel.state.library)
        }
    }

    // MARK: - UI state

    private func update(to state: CollectionsState) {
        if state.changes.contains(.results) {
            self.tableViewHandler.update(collections: state.collections, animated: true)
            self.collectionsChanged?(state.collections)
        }
        if state.changes.contains(.itemCount) {
            self.tableViewHandler.update(collections: state.collections, animated: false)
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
        self.viewModel.process(action: .startEditing(.add))
    }

    private func presentEditView(for data: CollectionStateEditingData) {
        let controller = UIHostingController(rootView: self.createEditView(for: data))
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.isModalInPresentation = true
        self.present(navigationController, animated: true, completion: nil)
    }

    private func createEditView(for data: CollectionStateEditingData) -> some View {
        let state = CollectionEditState(library: self.viewModel.state.library, key: data.0, name: data.1, parent: data.2)
        let handler = CollectionEditActionHandler(dbStorage: self.dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)

        return CollectionEditView(showPicker: { [weak self] library, selected, excluded in
            self?.showCollectionPicker(library: library, selected: selected, excluded: excluded, collectionEditViewModel: viewModel)
        }, closeAction: { [weak self] in
           self?.dismiss(animated: true, completion: nil)
        })
        .environment(\.dbStorage, self.dbStorage)
        .environmentObject(viewModel)
    }

    private func showCollectionPicker(library: Library, selected: String, excluded: Set<String>,
                                      collectionEditViewModel: ViewModel<CollectionEditActionHandler>) {
        let state = CollectionPickerState(library: library, excludedKeys: excluded, selected: [selected])
        let handler = CollectionPickerActionHandler(dbStorage: self.dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)

        // SWIFTUI BUG: - We need to call loadData here, because when we do so in `onAppear` in SwiftuI `View` we'll crash when data change
        // instantly in that function. If we delay it, the user will see unwanted animation of data on screen. If we call it here, data
        // is available immediately.
        viewModel.process(action: .loadData)

        let view = CollectionPickerView(saveAction: { [weak collectionEditViewModel] parent in
            collectionEditViewModel?.process(action: .setParent(parent))
        }).environmentObject(viewModel)
        let controller = UIHostingController(rootView: view)
        (self.presentedViewController as? UINavigationController)?.pushViewController(controller, animated: true)
    }

    // MARK: - Setups

    private func setupNavbarItems() {
        let item = UIBarButtonItem(image: UIImage(systemName: "plus"),
                                   style: .plain,
                                   target: self,
                                   action: #selector(CollectionsViewController.addCollection))
        self.navigationItem.rightBarButtonItem = item
    }
}
