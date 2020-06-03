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
        label.textColor = self.viewController.traitCollection.userInterfaceStyle == .light ? .black : .white
        label.textAlignment = .center

        var newItems = items
        newItems[1] = UIBarButtonItem(customView: label)
        controller.toolbar.setItems(newItems, animated: false)
    }

    // MARK: - Helpers

    private func text(for progress: SyncProgress) -> String {
        switch progress {
        case .starting:
            return L10n.SyncToolbar.starting
        case .groups(let progress):
            if let progress = progress {
                return L10n.SyncToolbar.groupsWithData(progress.completed, progress.total)
            }
            return L10n.SyncToolbar.groups
        case .library(let name):
            return L10n.SyncToolbar.library(name)
        case .object(let object, let progress, let library):
            if let progress = progress {
                return L10n.SyncToolbar.objectWithData(self.name(for: object), progress.completed, progress.total, library)
            }
            return L10n.SyncToolbar.object(self.name(for: object), library)
        case .changes(let progress):
            return L10n.SyncToolbar.writes(progress.completed, progress.total)
        case .uploads(let progress):
        return L10n.SyncToolbar.uploads(progress.completed, progress.total)
        case .finished(let errors):
            if errors.isEmpty {
                return L10n.SyncToolbar.finished
            }
            let issues = errors.count == 1 ? L10n.SyncToolbar.oneError : L10n.SyncToolbar.multipleErrors(errors.count)
            return L10n.SyncToolbar.finishedWithErrors(issues)
        case .deletions(let name):
            return  L10n.SyncToolbar.deletion(name)
        case .aborted(let error):
            return L10n.SyncToolbar.aborted(error.localizedDescription)
        }
    }

    private func name(for object: SyncObject) -> String {
        switch object {
        case .collection:
            return L10n.SyncToolbar.Object.collections
        case .item, .trash:
            return L10n.SyncToolbar.Object.items
        case .search:
            return L10n.SyncToolbar.Object.searches
        }
    }

    // MARK: - Setups

    private func setupToolbar(in controller: UINavigationController) {
        let spacer = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        spacer.width = 20
        controller.toolbarItems = [spacer, spacer, spacer]
    }
}
