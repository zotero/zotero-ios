//
//  ProgressToolbarViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 01/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjack
import RxCocoa
import RxSwift

class ProgressToolbarViewController: ToolbarViewController {
    private enum SyncButton {
        case sync, cancel
    }

    // Constants
    private let disposeBag: DisposeBag
    // Variables
    private weak var syncController: SyncController?
    private weak var titleLabel: UILabel!
    private weak var subtitleLabel: UILabel!
    private var syncButton: UIBarButtonItem = {
        return UIBarButtonItem(barButtonSystemItem: .refresh, target: self,
                               action: #selector(ProgressToolbarViewController.startSync))
    }()
    private var cancelSyncButton: UIBarButtonItem = {
        return UIBarButtonItem(title: "X", style: .plain, target: self,
                               action: #selector(ProgressToolbarViewController.cancelSync))
    }()

    // MARK: - Lifecycle

    init(syncController: SyncController?, rootViewController: UIViewController) {
        self.disposeBag = DisposeBag()
        self.syncController = syncController
        super.init(rootViewController: rootViewController)

        if syncController == nil {
            DDLogError("ProgressToolbarViewController: sync controller is nil!")
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupToolbarItems()
        if let observable = self.syncController?.progressObservable {
            self.setupObserving(for: observable)
        }
    }

    // MARK: - Actions

    @objc private func startSync() {
        self.syncController?.start()
        self.setSyncButton(to: .cancel)
    }

    @objc private func cancelSync() {
        self.syncController?.cancelSync()
        self.setSyncButton(to: .sync)
    }

    private func setSyncButton(to state: SyncButton) {
        guard var items = self.toolbar.items else { return }
        let item: UIBarButtonItem
        switch state {
        case .sync:
            item = self.syncButton
        case .cancel:
            item = self.cancelSyncButton
        }
        items[1] = item
        self.toolbar.setItems(items, animated: true)
    }

    private func process(state: SyncProgress?) {
        guard let state = state else {
            self.titleLabel.text = nil
            self.subtitleLabel.text = nil
            self.setSyncButton(to: .sync)
            return
        }

        switch state {
        case .groups:
            self.titleLabel.text = "Synchronizing groups"
            self.subtitleLabel.text = nil
            self.setSyncButton(to: .cancel)
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
            }
            var subtitle = "\(objectName)"
            if let progress = progress {
                let percentage = (Double(progress.0) / Double(progress.1)) * 100
                subtitle += String(format: " %.1f%%", percentage)
            } else {
                subtitle += " 0.0%"
            }
            self.titleLabel.text = "Synchronizing '\(libraryName)'"
            self.subtitleLabel.text = subtitle
        case .deletions(let libraryName):
            self.titleLabel.text = "Synchronizing '\(libraryName)'"
            self.subtitleLabel.text = "Removing deleted objects"
        case .finished(let errors):
            var text = "Synchronization finished"
            if !errors.isEmpty {
                text += " with \(errors.count) errors"
            }
            self.titleLabel.text = text
            self.subtitleLabel.text = nil
        case .aborted(let error):
            if let error = error as? SyncError, error == .cancelled {
                self.titleLabel.text = "Cancelled"
            } else {
                self.titleLabel.text = "Synchronization failed"
            }
            self.subtitleLabel.text = nil
        }
    }

    // MARK: - Setups

    private func setupObserving(for observable: BehaviorRelay<SyncProgress?>) {
        observable.observeOn(MainScheduler.instance)
                  .subscribe(onNext: { [weak self] state in
                      self?.process(state: state)
                  })
                  .disposed(by: self.disposeBag)
    }

    private func setupProgressView() -> UIView {
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

        self.titleLabel = titleLabel
        self.subtitleLabel = subtitleLabel

        return stackView
    }

    private func setupToolbarItems() {
        let buttonSpacer = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        buttonSpacer.width = 8
        let leftSpacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let rightSpacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let customView = UIBarButtonItem(customView: self.setupProgressView())
        self.toolbar.setItems([buttonSpacer, self.syncButton, leftSpacer, customView, rightSpacer], animated: false)
    }
}
