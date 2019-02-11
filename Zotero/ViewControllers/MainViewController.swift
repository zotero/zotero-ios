//
//  MainViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 11/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol ItemNavigationDelegate: class {
    func showItems(libraryId: Int, collectionId: String?)
    func hideItems()
}

class MainViewController: UISplitViewController {
    private let controllers: Controllers

    init(controllers: Controllers) {
        self.controllers = controllers

        super.init(nibName: nil, bundle: nil)

        let librariesStore = LibrariesStore(dbStorage: controllers.dbStorage)
        let leftController = LibrariesViewController(store: librariesStore, delegate: self)
        let leftNavigationController = UINavigationController(rootViewController: leftController)

        self.viewControllers = [leftNavigationController]
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }

    private func setSecondaryController(_ controller: UIViewController?) {
        var controllers = self.viewControllers
        if controllers.count == 1 {
            if let controller = controller {
                controllers.append(controller)
            }
        } else {
            if let controller = controller {
                controllers[1] = controller
            } else {
                controllers.remove(at: 1)
            }
        }
        self.viewControllers = controllers
    }
}

extension MainViewController: ItemNavigationDelegate {
    func showItems(libraryId: Int, collectionId: String?) {
        let state = ItemsState(libraryId: libraryId, collectionId: collectionId, parentId: nil, title: "")
        let store = ItemsStore(initialState: state, dbStorage: self.controllers.dbStorage)
        let controller = ItemsViewController(store: store)
        let navigationController = UINavigationController(rootViewController: controller)
        self.setSecondaryController(navigationController)
    }

    func hideItems() {
        self.setSecondaryController(nil)
    }
}
