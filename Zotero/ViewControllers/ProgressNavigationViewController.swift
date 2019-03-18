//
//  ProgressNavigationViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 01/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjack
import RxCocoa
import RxSwift

protocol ProgressToolbarController: class {
    var toolbarTitleLabel: UILabel? { get set }
    var toolbarSubtitleLabel: UILabel? { get set }
    var toolbarItems: [UIBarButtonItem]? { get }

    func setToolbarItems(_ toolbarItems: [UIBarButtonItem]?, animated: Bool)
}

class ProgressNavigationViewController: UINavigationController {
    // Constants
    private let disposeBag = DisposeBag()
    // Variables
    private var progressNavigationDelegate = ProgressNavigationDelegate()
    private var syncButton: UIBarButtonItem = {
        return UIBarButtonItem(barButtonSystemItem: .refresh, target: self,
                               action: #selector(ProgressNavigationViewController.startSync))
    }()
    private var cancelSyncButton: UIBarButtonItem = {
        return UIBarButtonItem(title: "X", style: .plain, target: self,
                               action: #selector(ProgressNavigationViewController.cancelSync))
    }()
    weak var syncScheduler: SynchronizationScheduler? {
        didSet {
            if let observable = self.syncScheduler?.progressObservable {
                self.setupObserving(for: observable)
            }
        }
    }
    private var progressController: ProgressToolbarController? {
        return self.topViewController as? ProgressToolbarController
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        self.progressNavigationDelegate.createItems = { [weak self] in
            return self?.createToolbarItems()
        }
        self.delegate = self.progressNavigationDelegate
        self.setToolbarHidden(false, animated: false)
    }

    // MARK: - Actions

    @objc private func startSync() {
        self.syncScheduler?.requestFullSync()
        self.setSyncButton(to: self.cancelSyncButton)
    }

    @objc private func cancelSync() {
        self.syncScheduler?.cancelSync()
        self.setSyncButton(to: self.syncButton)
    }

    private func process(state: SyncProgress?) {
        guard let controller = self.progressController else { return }

        guard let state = state else {
            controller.toolbarTitleLabel?.text = nil
            controller.toolbarSubtitleLabel?.text = nil
            self.setSyncButton(to: self.syncButton)
            return
        }

        let title: String
        let subtitle: String?
        var syncButton: UIBarButtonItem?

        switch state {
        case .groups:
            title = "Synchronizing groups"
            subtitle = nil
            syncButton = self.cancelSyncButton

        case .library(let libraryName, let object, let progress):
            let objectName: String
            switch object {
            case .group:
                return
            case .collection:
                objectName = "Collections"
            case .item:
                objectName = "Items"
            case .trash:
                objectName = "Trash"
            case .search:
                objectName = "Searches"
            case .tag:
                objectName = "Tags"
            }

            var progressSubtitle = "\(objectName)"
            if let progress = progress {
                let percentage = (Double(progress.0) / Double(progress.1)) * 100
                progressSubtitle += String(format: " %.1f%%", percentage)
            } else {
                progressSubtitle += " 0.0%"
            }
            title = "Synchronizing '\(libraryName)'"
            subtitle = progressSubtitle

        case .deletions(let libraryName):
            title = "Synchronizing '\(libraryName)'"
            subtitle = "Removing deleted objects"

        case .finished(let errors):
            var text = "Synchronization finished"
            if !errors.isEmpty {
                text += " with \(errors.count) errors"
            }
            title = text
            subtitle = nil
            
        case .aborted(let error):
            if let error = error as? SyncError, error == .cancelled {
                title = "Cancelled"
            } else {
                title = "Synchronization failed"
            }
            subtitle = nil
        }

        controller.toolbarTitleLabel?.text = title
        controller.toolbarSubtitleLabel?.text = subtitle
        if let button = syncButton {
            self.setSyncButton(to: button)
        }
    }

    private func setSyncButton(to button: UIBarButtonItem) {
        guard let controller = self.progressController,
              var items = controller.toolbarItems else { return }
        items[1] = button
        controller.setToolbarItems(items, animated: true)
    }

    private func createToolbarItems() -> ([UIBarButtonItem], UILabel, UILabel) {
        let buttonSpacer = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        buttonSpacer.width = 8
        let leftSpacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let rightSpacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let progressView = self.createProgressView()
        let customView = UIBarButtonItem(customView: progressView.0)
        return ([buttonSpacer, self.syncButton, leftSpacer, customView, rightSpacer], progressView.1, progressView.2)
    }

    private func createProgressView() -> (UIView, UILabel, UILabel) {
        let titleLabel = UILabel()
        titleLabel.font = UIFont.systemFont(ofSize: 14)
        let subtitleLabel = UILabel()
        subtitleLabel.font = UIFont.systemFont(ofSize: 12)
        subtitleLabel.textColor = .darkGray
        let stackView = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stackView.alignment = .center
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.heightAnchor.constraint(equalToConstant: 36.0).isActive = true
        return (stackView, titleLabel, subtitleLabel)
    }

    // MARK: - Setups

    private func setupObserving(for observable: BehaviorRelay<SyncProgress?>) {
        observable.observeOn(MainScheduler.instance)
                  .subscribe(onNext: { [weak self] state in
                    self?.process(state: state)
                  })
                  .disposed(by: self.disposeBag)
    }
}

class ProgressNavigationDelegate: NSObject, UINavigationControllerDelegate {
    var createItems: (() -> ([UIBarButtonItem], UILabel, UILabel)?)?

    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController, animated: Bool) {
        if let progressController = viewController as? ProgressToolbarController,
           let items = self.createItems?() {
            progressController.setToolbarItems(items.0, animated: false)
            progressController.toolbarTitleLabel = items.1
            progressController.toolbarSubtitleLabel = items.2
        }
    }
}
