//
//  SyncToolbarController.swift
//  Zotero
//
//  Created by Michal Rentka on 28/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class SyncToolbarController {
    private static let finishVisibilityTime: RxTimeInterval = .seconds(4)
    private unowned let viewController: UINavigationController
    private unowned let dbStorage: DbStorage
    private let disposeBag: DisposeBag

    private var pendingErrors: [Error]?
    private var timerDisposeBag: DisposeBag

    weak var coordinatorDelegate: MainCoordinatorSyncToolbarDelegate?

    init(parent: UINavigationController, progressObservable: PublishSubject<SyncProgress>, dbStorage: DbStorage) {
        self.viewController = parent
        self.dbStorage = dbStorage
        self.disposeBag = DisposeBag()
        self.timerDisposeBag = DisposeBag()

        parent.setToolbarHidden(true, animated: false)
        parent.toolbar.barTintColor = UIColor(dynamicProvider: { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? .black : .white
        })

        progressObservable.observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] progress in
                              guard let `self` = self else { return }
                              self.update(progress: progress, in: self.viewController)
                          })
                          .disposed(by: self.disposeBag)
    }

    // MARK: - Actions

    private func update(progress: SyncProgress, in controller: UINavigationController) {
        self.pendingErrors = nil

        switch progress {
        case .aborted(let error):
            switch error {
            case .cancelled:
                self.pendingErrors = nil
                self.timerDisposeBag = DisposeBag()
                if !controller.isToolbarHidden {
                    controller.setToolbarHidden(true, animated: true)
                }

            default:
                self.pendingErrors = [error]
                if controller.isToolbarHidden {
                    controller.setToolbarHidden(false, animated: true)
                }
                self.set(progress: progress, in: controller)
            }

        case .finished(let errors):
            if errors.isEmpty {
                self.pendingErrors = nil
                self.timerDisposeBag = DisposeBag()
                if !controller.isToolbarHidden {
                    controller.setToolbarHidden(true, animated: true)
                }
                return
            }

            self.pendingErrors = errors
            if controller.isToolbarHidden {
                controller.setToolbarHidden(false, animated: true)
            }
            self.set(progress: progress, in: controller)
            self.hideToolbarWithDelay(in: controller)

        case .starting:
            self.hideToolbarWithDelay(in: controller)

        default: break
        }
    }

    private func showErrorAlert(with errors: [Error]) {
        self.viewController.setToolbarHidden(true, animated: true)

        guard let error = errors.first else { return }
        
        let (message, data) = self.alertMessage(from: error)

        let controller = UIAlertController(title: L10n.error, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: { [weak self] _ in
            self?.pendingErrors = nil
        }))
        if let data = data, let keys = data.itemKeys, !keys.isEmpty {
            let title = keys.count == 1 ? L10n.Errors.SyncToolbar.showItem : L10n.Errors.SyncToolbar.showItems
            controller.addAction(UIAlertAction(title: title, style: .default, handler: { [weak self] _ in
                self?.coordinatorDelegate?.showItems(with: keys, in: data.libraryId)
            }))
        }
        self.viewController.present(controller, animated: true, completion: nil)
    }

    private func alertMessage(from error: Error) -> (message: String, additionalData: SyncError.ErrorData?) {
        if let error = error as? SyncError.Fatal {
            switch error {
            case .cancelled, .uploadObjectConflict: break // should not happen
            case .apiError(let response, let data):
                return (L10n.Errors.api(response), data)
            case .dbError:
                return (L10n.Errors.db, nil)
            case .allLibrariesFetchFailed:
                return (L10n.Errors.SyncToolbar.librariesMissing, nil)
            case .cantResolveConflict, .preconditionErrorCantBeResolved:
                return (L10n.Errors.SyncToolbar.conflictRetryLimit, nil)
            case .groupSyncFailed:
                return (L10n.Errors.SyncToolbar.groupsFailed, nil)
            case .missingGroupPermissions, .permissionLoadingFailed:
                return (L10n.Errors.SyncToolbar.groupPermissions, nil)
            case .noInternetConnection:
                return (L10n.Errors.SyncToolbar.internetConnection, nil)
            case .serviceUnavailable:
                return (L10n.Errors.SyncToolbar.unavailable, nil)
            }
        }

        if let error = error as? SyncError.NonFatal {
            switch error {
            case .schema:
                return (L10n.Errors.schema, nil)
            case .parsing:
                return (L10n.Errors.parsing, nil)
            case .apiError(let response, let data):
                return (L10n.Errors.api(response), data)
            case .versionMismatch:
                return (L10n.Errors.versionMismatch, nil)
            case .unknown(let _message):
                return _message.isEmpty ? (L10n.Errors.unknown, nil) : (_message, nil)
            case .attachmentMissing(let key, let libraryId, let title):
                return (L10n.Errors.SyncToolbar.attachmentMissing("\(title) (\(key))"), SyncError.ErrorData(itemKeys: [key], libraryId: libraryId))
            case .quotaLimit(let libraryId):
                switch libraryId {
                case .custom:
                    return (L10n.Errors.SyncToolbar.personalQuotaReached, nil)

                case .group(let groupId):
                    let group = try? self.dbStorage.perform(request: ReadGroupDbRequest(identifier: groupId), on: .main)
                    let groupName = group?.name ?? "\(groupId)"
                    return (L10n.Errors.SyncToolbar.groupQuotaReached(groupName), nil)
                }
            case .insufficientSpace:
                return (L10n.Errors.SyncToolbar.insufficientSpace, nil)
            case .webDavDeletionFailed(let error, _):
                return (L10n.Errors.SyncToolbar.webdavError(error), nil)
            case .webDavDeletion(let count, _):
                return (L10n.Errors.SyncToolbar.webdavError2(count), nil)
            case .webDavVerification(let error):
                return (error.message, nil)
            case .webDavDownload(let error):
                switch error {
                case .itemPropInvalid(let string):
                    return (L10n.Errors.SyncToolbar.webdavItemProp(string), nil)
                case .notChanged: break // Should not happen
                }
            case .annotationDidSplit(let string, _):
                return (string, nil)
            case .unchanged: break
            }
        }

        return ("", nil)
    }

    private func hideToolbarWithDelay(in controller: UINavigationController) {
        self.timerDisposeBag = DisposeBag()

        Single<Int>.timer(SyncToolbarController.finishVisibilityTime,
                          scheduler: MainScheduler.instance)
                   .subscribe(onSuccess: { [weak controller] _ in
                       controller?.setToolbarHidden(true, animated: true)
                   })
                   .disposed(by: self.timerDisposeBag)
    }

    private func set(progress: SyncProgress, in controller: UINavigationController) {
        let item = UIBarButtonItem(customView: self.toolbarView(with: self.text(for: progress)))
        controller.toolbar.setItems([item], animated: false)
    }

    private func toolbarView(with text: String) -> UIView {
        let textColor: UIColor = self.viewController.traitCollection.userInterfaceStyle == .light ? .black : .white
        let button = UIButton(frame: UIScreen.main.bounds)
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.numberOfLines = 2
        button.setTitleColor(textColor, for: .normal)
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.setTitle(text, for: .normal)

        button.rx
              .tap
              .observe(on: MainScheduler.instance)
              .subscribe(onNext: { [weak self] _ in
                  guard let errors = self?.pendingErrors else { return }
                  self?.showErrorAlert(with: errors)
              })
              .disposed(by: self.disposeBag)

        return button
    }

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
        case .object(let object, let progress, let libraryName, _):
            if let progress = progress {
                return L10n.SyncToolbar.objectWithData(self.name(for: object), progress.completed, progress.total, libraryName)
            }
            return L10n.SyncToolbar.object(self.name(for: object), libraryName)
        case .changes(let progress):
            return L10n.SyncToolbar.writes(progress.completed, progress.total)
        case .uploads(let progress):
        return L10n.SyncToolbar.uploads(progress.completed, progress.total)
        case .finished(let errors):
            if errors.isEmpty {
                return L10n.SyncToolbar.finished
            }
            let issues = errors.count == 1 ? L10n.Errors.SyncToolbar.oneError : L10n.Errors.SyncToolbar.multipleErrors(errors.count)
            return L10n.Errors.SyncToolbar.finishedWithErrors(issues)
        case .deletions(let name):
            return L10n.SyncToolbar.deletion(name)
        case .aborted(let error):
            return L10n.SyncToolbar.aborted(self.alertMessage(from: error).message)
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
        case .settings:
            return ""
        }
    }
}
