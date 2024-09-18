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
    
    var library: Library {
        return viewModel.state.library
    }
    
    var selectedItems: Set<String> {
        return []
    }
    
    func model(for item: RItem) -> ItemCellModel {
        // Create and cache attachment if needed
//        viewModel.process(action: .cacheItemAccessory(item: item))

//        let title: NSAttributedString
//        if let _title = viewModel.state.itemTitles[item.key] {
//            title = _title
//        } else {
//            viewModel.process(action: .cacheItemTitle(key: item.key, title: item.displayTitle))
//            title = viewModel.state.itemTitles[item.key, default: NSAttributedString()]
//        }

//        let accessory = viewModel.state.itemAccessories[item.key]
        let tmpTitle = NSAttributedString(string: item.displayTitle)
        let typeName = controllers.schemaController.localized(itemType: item.rawType) ?? item.rawType
        return ItemCellModel(item: item, typeName: typeName, title: tmpTitle, accessory: nil, fileDownloader: controllers.userControllers?.fileDownloader)
    }
    
    func accessory(forKey key: String) -> ItemAccessory? {
        return nil
    }
    
    func process(tapAction: ItemsTableViewHandler.TapAction) {
    }
    
    func process(action: ItemAction.Kind, for item: RItem, completionAction: ((Bool) -> Void)?) {
    }
    
    func createContextMenuActions(for item: RItem) -> [ItemAction] {
        return []
    }
}
