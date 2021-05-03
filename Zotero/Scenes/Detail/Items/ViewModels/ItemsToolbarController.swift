//
//  ItemsToolbarController.swift
//  Zotero
//
//  Created by Michal Rentka on 19.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RealmSwift
import RxSwift

protocol ItemsToolbarControllerDelegate: class {
    func process(action: ItemAction.Kind, button: UIBarButtonItem)
}

final class ItemsToolbarController {
    private static let barButtonItemEmptyTag = 1
    private static let barButtonItemSingleTag = 2
    private static let barButtonItemFilterTag = 3
    private static let barButtonItemTitleTag = 4
    private static let finishVisibilityTime: RxTimeInterval = .seconds(2)

    private unowned let viewController: UIViewController
    private let editingActions: [ItemAction]
    private let disposeBag: DisposeBag

//    private var pendingErrors: [Error]?
//    private weak var syncScheduler: SyncScheduler?
    private weak var delegate: ItemsToolbarControllerDelegate?

    init(viewController: UIViewController, initialState: ItemsState, delegate: ItemsToolbarControllerDelegate) {
        self.viewController = viewController
        self.delegate = delegate
        self.editingActions = ItemsToolbarController.editingActions(for: initialState)
        self.disposeBag = DisposeBag()

        self.createToolbarItems(for: initialState)
        self.viewController.navigationController?.setToolbarHidden(false, animated: false)

//        if let observable = syncScheduler?.syncController.progressObservable {
//            self.startObserving(observable: observable)
//        }
    }

    private static func editingActions(for state: ItemsState) -> [ItemAction] {
        var actions: [ItemAction] = []
        if state.type.isTrash {
            actions = [ItemAction(type: .restore), ItemAction(type: .delete)]
        } else {
            actions = [ItemAction(type: .addToCollection), ItemAction(type: .duplicate), ItemAction(type: .trash)]
            if state.type.collectionKey != nil {
                actions.insert(ItemAction(type: .removeFromCollection), at: 1)
            }
        }
        return actions
    }

    // MARK: - Actions

    func createToolbarItems(for state: ItemsState) {
        if state.isEditing {
            self.viewController.toolbarItems = self.createEditingToolbarItems(from: self.editingActions)
        } else {
            self.viewController.toolbarItems = self.createNormalToolbarItems(for: state.filters)
        }
    }

    func reloadToolbarItems(for state: ItemsState) {
        if state.isEditing {
            self.updateEditingToolbarItems(for: state.selectedItems)
        } else {
            self.updateFilteringToolbarItems(for: state.filters, results: state.results)
        }
    }

//    private func update(to progress: SyncProgress) {
//        self.pendingErrors = nil
//
//        switch progress {
//        case .aborted(let error):
//            switch error {
//            case .cancelled: break
//            default:
//                self.pendingErrors = [error]
//            }
//
//        case .finished(let errors):
//            if errors.isEmpty {
//                self.pendingErrors = nil
////                self.hideToolbarWithDelay(in: controller)
//            } else {
//                self.pendingErrors = errors
//            }
//
//        default: break
//        }
//    }

    // MARK: - Helpers

    private func updateEditingToolbarItems(for selectedItems: Set<String>) {
        self.viewController.toolbarItems?.forEach({ item in
            switch item.tag {
            case ItemsToolbarController.barButtonItemEmptyTag:
                item.isEnabled = !selectedItems.isEmpty
            case ItemsToolbarController.barButtonItemSingleTag:
                item.isEnabled = selectedItems.count == 1
            default: break
            }
        })
    }

    private func updateFilteringToolbarItems(for filters: [ItemsState.Filter], results: Results<RItem>?) {
        if let item = self.viewController.toolbarItems?.first(where: { $0.tag == ItemsToolbarController.barButtonItemFilterTag }) {
            let filterImageName = filters.isEmpty ? "line.horizontal.3.decrease.circle" : "line.horizontal.3.decrease.circle.fill"
            item.image = UIImage(systemName: filterImageName)
        }

        if let item = self.viewController.toolbarItems?.first(where: { $0.tag == ItemsToolbarController.barButtonItemTitleTag }),
           let label = item.customView as? UILabel {
            let itemCount = results?.count ?? 0
            label.text = filters.isEmpty ? "" : "Filter: \(itemCount) item\(itemCount == 1 ? "" : "s")"
            label.sizeToFit()
        }
    }

    private func createNormalToolbarItems(for filters: [ItemsState.Filter]) -> [UIBarButtonItem] {
        let fixedSpacer = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        fixedSpacer.width = 16
        let flexibleSpacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        let filterImageName = filters.isEmpty ? "line.horizontal.3.decrease.circle" : "line.horizontal.3.decrease.circle.fill"
        let filterButton = UIBarButtonItem(image: UIImage(systemName: filterImageName), style: .plain, target: nil, action: nil)
        filterButton.tag = ItemsToolbarController.barButtonItemFilterTag
        filterButton.rx.tap.subscribe(onNext: { [weak self] _ in
            self?.delegate?.process(action: .filter, button: filterButton)
        })
        .disposed(by: self.disposeBag)

        let addButton = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: nil, action: nil)
        addButton.rx.tap.subscribe(onNext: { [weak self] _ in
            self?.delegate?.process(action: .add, button: addButton)
        })
        .disposed(by: self.disposeBag)

        let titleButton = UIBarButtonItem(customView: self.createTitleView())
        titleButton.tag = ItemsToolbarController.barButtonItemTitleTag

        return [fixedSpacer, filterButton, flexibleSpacer, titleButton, flexibleSpacer, addButton, fixedSpacer]
    }

    private func createEditingToolbarItems(from actions: [ItemAction]) -> [UIBarButtonItem] {
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let items = actions.map({ action -> UIBarButtonItem in
            let item = UIBarButtonItem(image: action.image, style: .plain, target: nil, action: nil)
            switch action.type {
            case .addToCollection, .trash, .delete, .removeFromCollection, .restore:
                item.tag = ItemsToolbarController.barButtonItemEmptyTag
            case .duplicate:
                item.tag = ItemsToolbarController.barButtonItemSingleTag
            case .add, .filter, .createParent: break
            }
            item.rx.tap.subscribe(onNext: { [weak self] _ in
                guard let `self` = self else { return }
                self.delegate?.process(action: action.type, button: item)
            })
            .disposed(by: self.disposeBag)
            return item
        })
        return [spacer] + (0..<(2 * items.count)).map({ idx -> UIBarButtonItem in idx % 2 == 0 ? items[idx/2] : spacer })
    }

//    private func showErrorAlert(with errors: [Error]) {
//        // TODO: clear pending errors
//        // TODO: switch to default title
//        let controller = UIAlertController(title: L10n.error, message: self.alertMessage(from: errors), preferredStyle: .alert)
//        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
//        self.viewController.present(controller, animated: true, completion: nil)
//    }

//    private func alertMessage(from errors: [Error]) -> String {
//        var message = ""
//
//        for (idx, error) in errors.enumerated() {
//            if let error = error as? SyncError.Fatal {
//                switch error {
//                case .cancelled, .uploadObjectConflict: return "" // should not happen
//                case .apiError(let response):
//                    message += L10n.Errors.api(response)
//                case .dbError:
//                    message += L10n.Errors.db
//                case .attachmentMissing(let key, let title):
//                    message += L10n.Errors.SyncToolbar.attachmentMissing("\(title) (\(key))")
//                case .allLibrariesFetchFailed:
//                    message += L10n.Errors.SyncToolbar.librariesMissing
//                case .cantResolveConflict, .preconditionErrorCantBeResolved:
//                    message += L10n.Errors.SyncToolbar.conflictRetryLimit
//                case .groupSyncFailed:
//                    message += L10n.Errors.SyncToolbar.groupsFailed
//                case .missingGroupPermissions, .permissionLoadingFailed:
//                    message += L10n.Errors.SyncToolbar.groupPermissions
//                case .noInternetConnection:
//                    message += L10n.Errors.SyncToolbar.internetConnection
//                }
//            } else if let error = error as? SyncError.NonFatal {
//                switch error {
//                case .schema:
//                    message += L10n.Errors.schema
//                case .parsing:
//                    message += L10n.Errors.parsing
//                case .apiError(let response):
//                    message += L10n.Errors.api(response)
//                case .versionMismatch:
//                    message += L10n.Errors.versionMismatch
//                case .unknown:
//                    message += L10n.Errors.unknown
//                }
//            }
//
//            if idx != errors.count - 1 {
//                message += "\n\n"
//            }
//        }
//
//        return message
//    }

    private func createTitleView() -> UILabel {
        let label = UILabel()
//        label.textColor = UIColor(dynamicProvider: { traitCollection -> UIColor in
//            return traitCollection.userInterfaceStyle == .dark ? .white : .black
//        })
        label.textColor = .black
        label.textAlignment = .center
        return label
    }

//    private func title(for progress: SyncProgress) -> String {
//        switch progress {
//        case .starting:
//            return L10n.SyncToolbar.starting
//        case .groups(let progress):
//            if let progress = progress {
//                return L10n.SyncToolbar.groupsWithData(progress.completed, progress.total)
//            }
//            return L10n.SyncToolbar.groups
//        case .library(let name):
//            return L10n.SyncToolbar.library(name)
//        case .object(let object, let progress, let libraryName, _):
//            if let progress = progress {
//                return L10n.SyncToolbar.objectWithData(self.name(for: object), progress.completed, progress.total, libraryName)
//            }
//            return L10n.SyncToolbar.object(self.name(for: object), libraryName)
//        case .changes(let progress):
//            return L10n.SyncToolbar.writes(progress.completed, progress.total)
//        case .uploads(let progress):
//        return L10n.SyncToolbar.uploads(progress.completed, progress.total)
//        case .finished(let errors):
//            if errors.isEmpty {
//                return L10n.SyncToolbar.finished
//            }
//            let issues = errors.count == 1 ? L10n.Errors.SyncToolbar.oneError : L10n.Errors.SyncToolbar.multipleErrors(errors.count)
//            return L10n.Errors.SyncToolbar.finishedWithErrors(issues)
//        case .deletions(let name):
//            return  L10n.SyncToolbar.deletion(name)
//        case .aborted(let error):
//            return L10n.SyncToolbar.aborted(self.alertMessage(from: [error]))
//        }
//    }
//
//    private func name(for object: SyncObject) -> String {
//        switch object {
//        case .collection:
//            return L10n.SyncToolbar.Object.collections
//        case .item, .trash:
//            return L10n.SyncToolbar.Object.items
//        case .search:
//            return L10n.SyncToolbar.Object.searches
//        case .settings:
//            return ""
//        }
//    }
//
//    private func startObserving(observable: PublishSubject<SyncProgress>) {
//        observable.observeOn(MainScheduler.instance)
//                  .subscribe(onNext: { [weak self] progress in
//                      self?.update(to: progress)
//                  })
//                  .disposed(by: self.disposeBag)
//    }
}
