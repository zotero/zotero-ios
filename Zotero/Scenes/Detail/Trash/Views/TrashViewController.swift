//
//  TrashViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 18.07.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class TrashViewController: UIViewController {
    private let viewModel: ViewModel<TrashActionHandler>
    private unowned let controllers: Controllers
    private let disposeBag: DisposeBag

    private weak var tableView: UITableView!
    private var tableViewHandler: ItemsTableViewHandler!

    init(viewModel: ViewModel<TrashActionHandler>, controllers: Controllers) {
        self.viewModel = viewModel
        self.controllers = controllers
        disposeBag = DisposeBag()

        super.init(nibName: nil, bundle: nil)

        viewModel.process(action: .loadData)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        createTableView()
        tableViewHandler = ItemsTableViewHandler(tableView: tableView, delegate: self, dragDropController: controllers.dragDropController)

        viewModel
            .stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(state: state)
            })
            .disposed(by: self.disposeBag)

        func createTableView() {
            let tableView = UITableView()
            tableView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(tableView)

            NSLayoutConstraint.activate([
                tableView.topAnchor.constraint(equalTo: view.topAnchor),
                tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])

            self.tableView = tableView
        }
    }

    private func update(state: TrashState) {
    }
}

extension TrashViewController: ItemsTableViewHandlerDelegate {
    var isInViewHierarchy: Bool {
        return view.window != nil
    }
    
    var collectionKey: String? {
        return nil
    }
    
    var library: Library {
        return viewModel.state.library
    }
    
    func process(action: ItemAction.Kind, at index: Int, completionAction: ((Bool) -> Void)?) {
    }
    
    func process(tapAction action: ItemsTableViewHandler.TapAction) {
    }
    
    func process(dragAndDropAction action: ItemsTableViewHandler.DragAndDropAction) {
    }
}
