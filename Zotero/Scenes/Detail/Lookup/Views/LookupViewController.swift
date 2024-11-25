//
//  LookupViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 17.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RxSwift

class LookupViewController: UIViewController {
    enum Row: Hashable {
        struct Item: Hashable, Equatable {
            let type: String
            let title: String
        }

        enum IdentifierState {
            case enqueued
            case inProgress
            case failed
        }

        case identifier(identifier: String, state: IdentifierState)
        case item(Item)
        case attachment(Attachment, RemoteAttachmentDownloader.Update.Kind)

        func isAttachment(withKey key: String, libraryId: LibraryIdentifier) -> Bool {
            switch self {
            case .attachment(let attachment, _):
                return attachment.key == key && attachment.libraryId == libraryId

            case .item, .identifier:
                return false
            }
        }
    }

    @IBOutlet private weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var tableView: UITableView!
    @IBOutlet private weak var tableViewHeight: NSLayoutConstraint!
    @IBOutlet private weak var errorLabel: UILabel!

    private var dataSource: UITableViewDiffableDataSource<Int, Row>!
    private var contentSizeObserver: NSKeyValueObservation?
    var dataReloaded: (() -> Void)?
    var activeLookupsFinished: (() -> Void)?

    private static let iconWidth: CGFloat = 28
    let viewModel: ViewModel<LookupActionHandler>
    private unowned let remoteFileDownloader: RemoteAttachmentDownloader
    private unowned let schemaController: SchemaController
    private let disposeBag: DisposeBag
    private let updateQueue: DispatchQueue

    init(
        viewModel: ViewModel<LookupActionHandler>,
        remoteDownloadObserver: PublishSubject<RemoteAttachmentDownloader.Update>,
        remoteFileDownloader: RemoteAttachmentDownloader,
        schemaController: SchemaController
    ) {
        self.viewModel = viewModel
        self.remoteFileDownloader = remoteFileDownloader
        self.schemaController = schemaController
        self.disposeBag = DisposeBag()
        updateQueue = DispatchQueue(label: "org.zotero.LookupViewController.UpdateQueue")
        super.init(nibName: "LookupViewController", bundle: nil)
        self.setupAttachmentObserving(observer: remoteDownloadObserver)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupTableView()
        if self.viewModel.state.hasDarkBackground {
            self.activityIndicator.color = .white
        }
        self.update(state: self.viewModel.state)

        self.viewModel.stateObservable
                      .subscribe(with: self, onNext: { `self`, state in
                          self.update(state: state)
                      })
                      .disposed(by: self.disposeBag)

        self.viewModel.process(action: .initialize)
    }

    deinit {
        DDLogInfo("LookupViewController: deinitialized")
    }

    // MARK: - Actions

    private func update(state: LookupState) {
        switch state.lookupState {
        case .failed(let error):
            tableView.isHidden = true
            activityIndicator.stopAnimating()
            activityIndicator.isHidden = true
            errorLabel.text = error.localizedDescription
            errorLabel.isHidden = false

        case .waitingInput:
            tableView.isHidden = true
            errorLabel.isHidden = true
            activityIndicator.stopAnimating()
            activityIndicator.isHidden = true

        case .loadingIdentifiers:
            tableView.isHidden = true
            errorLabel.isHidden = true
            activityIndicator.isHidden = false
            activityIndicator.startAnimating()

        case .lookup(let data):
            // It takes a little while for the `contentSize` observer notification to come, so all the content is hidden after the notification arrives, so that there is not an empty screen while
            // waiting for it.
            show(data: data) { [weak self] in
                guard let self else { return }
                activityIndicator.stopAnimating()
                activityIndicator.isHidden = true
                errorLabel.isHidden = true
                tableView.isHidden = false
                dataReloaded?()
                closeAfterUpdateIfNeeded()
            }
        }
    }

    private func show(data: [LookupState.LookupData], completion: @escaping () -> Void) {
        tableView.isHidden = false

        updateQueue.async { [weak self] in
            guard let self else { return }

            let snapshot = createSnapshot(from: data, schemaController: schemaController, remoteFileDownloader: remoteFileDownloader)
            dataSource.apply(snapshot, animatingDifferences: false)

            guard contentSizeObserver == nil else {
                inMainThread {
                    completion()
                }
                return
            }

            // For some reason, the observer subscription has to be here, doesn't work if it's in `viewDidLoad`.
            contentSizeObserver = tableView.observe(\.contentSize, options: [.new]) { [weak self] _, change in
                inMainThread { [weak self] in
                    guard let self, let value = change.newValue, value.height != tableViewHeight.constant else { return }
                    tableViewHeight.constant = value.height
                    if value.height >= self.tableView.frame.height, !tableView.isScrollEnabled {
                        tableView.isScrollEnabled = true
                    }
                    completion()
                }
            }
        }

        func createSnapshot(from data: [LookupState.LookupData], schemaController: SchemaController, remoteFileDownloader: RemoteAttachmentDownloader) -> NSDiffableDataSourceSnapshot<Int, Row> {
            var snapshot = NSDiffableDataSourceSnapshot<Int, Row>()
            snapshot.appendSections([0])

            for lookup in data {
                switch lookup.state {
                case .translated(let translationData):
                    let title: String
                    if let _title = translationData.response.fields[KeyBaseKeyPair(key: FieldKeys.Item.title, baseKey: nil)] {
                        title = _title
                    } else {
                        let _title = translationData.response.fields.first(where: { schemaController.baseKey(for: translationData.response.rawType, field: $0.key.key) == FieldKeys.Item.title })?.value
                        title = _title ?? ""
                    }
                    let itemData = Row.Item(type: translationData.response.rawType, title: title)

                    snapshot.appendItems([.item(itemData)], toSection: 0)

                    let attachments = translationData.attachments.map({ attachment -> Row in
                        let (progress, error) = remoteFileDownloader.data(for: attachment.0.key, parentKey: translationData.response.key, libraryId: attachment.0.libraryId)
                        let updateKind: RemoteAttachmentDownloader.Update.Kind
                        if error != nil {
                            updateKind = .failed
                        } else if let progress = progress {
                            updateKind = .progress(progress)
                        } else {
                            updateKind = .ready(attachment.0)
                        }
                        return .attachment(attachment.0, updateKind)
                    })
                    snapshot.appendItems(attachments, toSection: 0)

                case .failed:
                    snapshot.appendItems([.identifier(identifier: lookup.identifier, state: .failed)])

                case .inProgress:
                    snapshot.appendItems([.identifier(identifier: lookup.identifier, state: .inProgress)])

                case .enqueued:
                    snapshot.appendItems([.identifier(identifier: lookup.identifier, state: .enqueued)])
                }
            }

            return snapshot
        }
    }

    private func process(update: RemoteAttachmentDownloader.Update, completed: @escaping () -> Void) {
        guard update.download.libraryId == viewModel.state.libraryId, var snapshot = dataSource?.snapshot(), !snapshot.sectionIdentifiers.isEmpty else { return }

        updateQueue.async { [weak self] in
            guard let self else { return }

            var rows = snapshot.itemIdentifiers(inSection: 0)
            guard let index = rows.firstIndex(where: { $0.isAttachment(withKey: update.download.key, libraryId: update.download.libraryId) }) else { return }
            snapshot.deleteItems(rows)
            let row = rows[index]
            switch row {
            case .attachment(let attachment, _):
                rows[index] = .attachment(attachment, update.kind)

            case .item, .identifier:
                break
            }
            snapshot.appendItems(rows, toSection: 0)
            dataSource.apply(snapshot, animatingDifferences: false)

            inMainThread {
                completed()
            }
        }
    }

    private func closeAfterUpdateIfNeeded() {
        let itemIdentifiers = dataSource.snapshot().itemIdentifiers
        guard !itemIdentifiers.isEmpty else { return }
        let hasActiveDownload = itemIdentifiers.contains { row in
            switch row {
            case .attachment(_, let update):
                switch update {
                case .progress, .failed:
                    return true

                default:
                    return false
                }

            case .identifier:
                return true

            case .item:
                return false
            }
        }
        if !hasActiveDownload {
            self.activeLookupsFinished?()
        }
    }

    // MARK: - Setups

    private func setupTableView() {
        self.tableViewHeight.constant = 0
        self.tableView.register(UINib(nibName: "LookupItemCell", bundle: nil), forCellReuseIdentifier: "LookupCell")
        self.tableView.register(UINib(nibName: "LookupIdentifierCell", bundle: nil), forCellReuseIdentifier: "IdentifierCell")
        self.tableView.isScrollEnabled = false
        self.tableView.backgroundColor = .clear
        self.tableView.backgroundView = UIView()

        self.dataSource = UITableViewDiffableDataSource(tableView: self.tableView, cellProvider: { [weak self] tableView, indexPath, row in
            let cellId: String
            switch row {
            case .identifier:
                cellId = "IdentifierCell"
                
            case .item, .attachment:
                cellId = "LookupCell"
            }

            let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath)

            guard let self = self else { return cell }

            var separatorInset: CGFloat = 0

            switch row {
            case .item(let data):
                if let cell = cell as? LookupItemCell {
                    separatorInset = LookupViewController.iconWidth + LookupItemCell.attachmentToLabelOffset
                    cell.set(title: data.title, type: data.type, hasDarkBackground: self.viewModel.state.hasDarkBackground)
                }

            case .attachment(let attachment, let update):
                if let cell = cell as? LookupItemCell {
                    cell.set(title: attachment.title, attachmentType: attachment.type, update: update, hasDarkBackground: self.viewModel.state.hasDarkBackground)
                    separatorInset = LookupViewController.iconWidth + LookupItemCell.attachmentToLabelOffset + LookupItemCell.attachmentOffset
                }

            case .identifier(let identifier, let state):
                if let cell = cell as? LookupIdentifierCell {
                    cell.set(title: identifier, state: state, hasDarkBackground: self.viewModel.state.hasDarkBackground)
                }
            }

            cell.separatorInset = UIEdgeInsets(top: 0, left: separatorInset, bottom: 0, right: 0)
            cell.selectionStyle = .none

            return cell
        })
    }

    private func setupAttachmentObserving(observer: PublishSubject<RemoteAttachmentDownloader.Update>) {
        observer.observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] update in
                    self?.process(update: update) { [weak self] in
                        self?.closeAfterUpdateIfNeeded()
                    }
                })
                .disposed(by: self.disposeBag)
    }
}
