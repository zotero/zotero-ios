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
    private unowned let viewController: UIViewController
    private unowned let dbStorage: DbStorage
    private let disposeBag: DisposeBag

    private var toolbar: UIToolbar!
    private var toolbarBottom: NSLayoutConstraint!
    private var pendingErrors: [Error]?
    private var timerDisposeBag: DisposeBag
    private var toolbarIsHidden: Bool {
        return toolbarBottom.constant != 0
    }

    weak var coordinatorDelegate: MainCoordinatorSyncToolbarDelegate?

    init(parent: UIViewController, progressObservable: PublishSubject<SyncProgress>, dbStorage: DbStorage) {
        viewController = parent
        self.dbStorage = dbStorage
        disposeBag = DisposeBag()
        timerDisposeBag = DisposeBag()
        setupToolbar()

        setToolbar(hidden: true, animated: false)
        progressObservable.observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] progress in
                              update(progress: progress)
                          })
                          .disposed(by: disposeBag)

        func setupToolbar() {
            let toolbar = UIToolbar()
            toolbar.barTintColor = UIColor(dynamicProvider: { traitCollection in
                return traitCollection.userInterfaceStyle == .dark ? .black : .white
            })
            toolbar.translatesAutoresizingMaskIntoConstraints = false
            parent.view.addSubview(toolbar)
            self.toolbar = toolbar

            let bottom = parent.view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor)
            toolbarBottom = bottom

            NSLayoutConstraint.activate([
                toolbar.heightAnchor.constraint(equalToConstant: 45),
                toolbar.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
                toolbar.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
                bottom
            ])

            parent.view.layoutIfNeeded()
        }
    }

    // MARK: - Actions

    private func update(progress: SyncProgress) {
        pendingErrors = nil

        switch progress {
        case .aborted(let error):
            switch error {
            case .cancelled:
                pendingErrors = nil
                timerDisposeBag = DisposeBag()
                if !toolbarIsHidden {
                    setToolbar(hidden: true, animated: true)
                }

            default:
                pendingErrors = [error]
                if toolbarIsHidden {
                    setToolbar(hidden: false, animated: true)
                }
                set(progress: progress)
            }

        case .finished(let errors):
            if errors.isEmpty {
                pendingErrors = nil
                timerDisposeBag = DisposeBag()
                if !toolbarIsHidden {
                    setToolbar(hidden: true, animated: true)
                }
                return
            }

            pendingErrors = errors
            if toolbarIsHidden {
                setToolbar(hidden: false, animated: true)
            }
            set(progress: progress)
            hideToolbarWithDelay()

        case .starting:
            hideToolbarWithDelay()

        default: break
        }
    }

    private func showErrorAlert(with errors: [Error]) {
        setToolbar(hidden: true, animated: true)

        guard let error = errors.first else { return }
        
        let (message, data) = alertMessage(from: error)

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
        viewController.present(controller, animated: true, completion: nil)
    }

    private func alertMessage(from error: Error) -> (message: String, additionalData: SyncError.ErrorData?) {
        if let error = error as? SyncError.Fatal {
            switch error {
            case .cancelled: // should not happen
                break

            case .apiError(let response, let data):
                return (L10n.Errors.api(response), data)

            case .dbError:
                return (L10n.Errors.db, nil)

            case .allLibrariesFetchFailed:
                return (L10n.Errors.SyncToolbar.librariesMissing, nil)

            case .uploadObjectConflict:
                return (L10n.Errors.SyncToolbar.conflictRetryLimit, nil)

            case .groupSyncFailed:
                return (L10n.Errors.SyncToolbar.groupsFailed, nil)

            case .missingGroupPermissions, .permissionLoadingFailed:
                return (L10n.Errors.SyncToolbar.groupPermissions, nil)

            case .noInternetConnection:
                return (L10n.Errors.SyncToolbar.internetConnection, nil)

            case .serviceUnavailable:
                return (L10n.Errors.SyncToolbar.unavailable, nil)

            case .forbidden:
                return (L10n.Errors.SyncToolbar.forbiddenMessage, nil)

            case .cantSubmitAttachmentItem(let data):
                return (L10n.Errors.db, data)
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

            case .unknown(let _message, let data):
                return _message.isEmpty ? (L10n.Errors.unknown, data) : (_message, data)

            case .attachmentMissing(let key, let libraryId, let title):
                return (L10n.Errors.SyncToolbar.attachmentMissing("\(title) (\(key))"), SyncError.ErrorData(itemKeys: [key], libraryId: libraryId))

            case .quotaLimit(let libraryId):
                switch libraryId {
                case .custom:
                    return (L10n.Errors.SyncToolbar.personalQuotaReached, nil)

                case .group(let groupId):
                    let group = try? dbStorage.perform(request: ReadGroupDbRequest(identifier: groupId), on: .main)
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

                case .notChanged: // Should not happen
                    break
                }

            case .webDavUpload(let error):
                switch error {
                case .cantCreatePropData: // Should not happen
                    break

                case .apiError(let error, let httpMethod):
                    guard let statusCode = error.unacceptableStatusCode else { break }
                    return (L10n.Errors.SyncToolbar.webdavRequestFailed(statusCode, httpMethod ?? "Unknown"), nil)
                }

            case .annotationDidSplit(let string, let keys, let libraryId):
                return (string, SyncError.ErrorData(itemKeys: Array(keys), libraryId: libraryId))

            case .unchanged:
                break

            case .preconditionFailed(let libraryId):
                return (L10n.Errors.SyncToolbar.conflictRetryLimit, SyncError.ErrorData(itemKeys: nil, libraryId: libraryId))
            }
        }

        return ("", nil)
    }

    private func setToolbar(hidden: Bool, animated: Bool) {
        toolbarBottom.constant = hidden ? -((viewController.splitViewController?.view.safeAreaInsets.bottom ?? viewController.view.safeAreaInsets.bottom) + toolbar.frame.height) : 0

        if !animated {
            viewController.view.layoutIfNeeded()
            return
        }

        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut], animations: { [weak self] in
            self?.viewController.view.layoutIfNeeded()
        })
    }

    private func hideToolbarWithDelay() {
        timerDisposeBag = DisposeBag()
        Single<Int>.timer(SyncToolbarController.finishVisibilityTime,
                          scheduler: MainScheduler.instance)
                   .subscribe(onSuccess: { [weak self] _ in
                       self?.setToolbar(hidden: true, animated: true)
                   })
                   .disposed(by: timerDisposeBag)
    }

    private func set(progress: SyncProgress) {
        let item = UIBarButtonItem(customView: toolbarView(with: text(for: progress)))
        toolbar.setItems([item], animated: false)
    }

    private func toolbarView(with text: String) -> UIView {
        let textColor: UIColor = viewController.traitCollection.userInterfaceStyle == .light ? .black : .white
        let button = UIButton(frame: UIScreen.main.bounds)
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.numberOfLines = 2
        button.setTitleColor(textColor, for: .normal)
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.setTitle(text, for: .normal)

        button
            .rx
            .tap
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] _ in
                guard let self, let pendingErrors else { return }
                showErrorAlert(with: pendingErrors)
            })
            .disposed(by: disposeBag)

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
                return L10n.SyncToolbar.objectWithData(name(for: object), progress.completed, progress.total, libraryName)
            }
            return L10n.SyncToolbar.object(name(for: object), libraryName)

        case .changes(let progress):
            return L10n.SyncToolbar.writes(progress.completed, progress.total)

        case .uploads(let progress):
        return L10n.SyncToolbar.uploads(progress.completed, progress.total)

        case .finished(let errors):
            if errors.isEmpty {
                return L10n.SyncToolbar.finished
            }
            let issues = L10n.Errors.SyncToolbar.errors(errors.count)
            return L10n.Errors.SyncToolbar.finishedWithErrors(issues)

        case .deletions(let name):
            return L10n.SyncToolbar.deletion(name)

        case .aborted(let error):
            if case .forbidden = error {
                return L10n.Errors.SyncToolbar.forbidden
            }
            return L10n.SyncToolbar.aborted(alertMessage(from: error).message)
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
