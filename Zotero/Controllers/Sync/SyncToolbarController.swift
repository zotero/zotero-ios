//
//  SyncToolbarController.swift
//  Zotero
//
//  Created by Michal Rentka on 28/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxCocoa
import RxSwift

class SyncToolbarController {
    private unowned let viewController: UINavigationController
    private let disposeBag: DisposeBag

    init(parent: UINavigationController, progressObservable: BehaviorRelay<SyncProgress?>) {
        self.viewController = parent
        self.disposeBag = DisposeBag()

        self.setupToolbar(in: parent)

        progressObservable.observeOn(MainScheduler.instance)
                          .subscribe(onNext: { [weak self] progress in
                              guard let `self` = self else { return }
                              self.update(progress: progress, in: self.viewController)
                          })
                          .disposed(by: self.disposeBag)
    }

    // MARK: - Actions

    private func update(progress: SyncProgress?, in controller: UINavigationController) {
        if let progress = progress {
            controller.setToolbarHidden(false, animated: true)
            self.set(text: self.text(for: progress), in: controller)
        } else {
            controller.setToolbarHidden(true, animated: true)
        }
    }

    private func set(text: String, in controller: UINavigationController) {
        guard let items = controller.toolbarItems else { return }

        let label = UILabel(frame: UIScreen.main.bounds)
        label.font = .preferredFont(forTextStyle: .body)
        label.text = text
        label.adjustsFontSizeToFitWidth = true
        label.numberOfLines = 2
        label.textColor = .black
        label.textAlignment = .center

        var newItems = items
        newItems[1] = UIBarButtonItem(customView: label)
        controller.toolbar.setItems(newItems, animated: false)
    }

    // MARK: - Helpers

    private func text(for progress: SyncProgress) -> String {
        switch progress {
        case .starting:
            return "Sync starting"
        case .groups:
            return "Syncing groups"
        case .library(let name, let type, let data):
            var message = "Syncing \(self.name(for: type))"
            if let data = data {
                message += " (\(data.completed) / \(data.total))"
            }
            message += " in \"\(name)\""
            return message
        case .finished(let errors):
            var message = "Finished sync"
            if !errors.isEmpty {
                message += " (\(errors.count) issue\(errors.count == 1 ? "" : "s"))"
            }
            return message
        case .deletions(let name):
            return "Removing unused objects in \(name)"
        case .aborted(let error):
            return "Sync failed (\(error.localizedDescription))"
        }
    }

    private func name(for object: SyncObject) -> String {
        switch object {
        case .collection:
            return "collections"
        case .group:
            return "groups"
        case .item, .trash:
            return "items"
        case .search:
            return "searches"
        case .tag:
            return "tags"
        }
    }

    // MARK: - Setups

    private func setupToolbar(in controller: UINavigationController) {
        let spacer = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        spacer.width = 20
        controller.toolbarItems = [spacer, spacer, spacer]
    }
}
