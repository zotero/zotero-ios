//
//  LookupViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 17.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

import RxSwift

class LookupViewController: UIViewController {
    private struct ItemData: Hashable, Equatable {
        let type: String
        let title: String
    }

    private enum Row: Hashable {
        case item(ItemData)
        case attachment(Attachment, RemoteAttachmentDownloader.Update.Kind)

        func isAttachment(withKey key: String, libraryId: LibraryIdentifier) -> Bool {
            switch self {
            case .attachment(let attachment, _):
                return attachment.key == key && attachment.libraryId == libraryId
            case .item:
                return false
            }
        }
    }

    @IBOutlet private weak var webView: WKWebView!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var inputContainer: UIStackView!
    @IBOutlet private weak var textField: UITextField!
    @IBOutlet private weak var tableView: UITableView!
    @IBOutlet private weak var tableViewHeight: NSLayoutConstraint!
    @IBOutlet private weak var errorLabel: UILabel!
    @IBOutlet private weak var topConstraint: NSLayoutConstraint!
    @IBOutlet private var padBottomConstraint: NSLayoutConstraint!
    @IBOutlet private var phoneBottomConstraint: NSLayoutConstraint!

    private var dataSource: UITableViewDiffableDataSource<Int, Row>!
    private var contentSizeObserver: NSKeyValueObservation?

    private static let width: CGFloat = 500
    private static let iconWidth: CGFloat = 28
    private let viewModel: ViewModel<LookupActionHandler>
    private unowned let schemaController: SchemaController
    private let disposeBag: DisposeBag

    init(viewModel: ViewModel<LookupActionHandler>, remoteDownloadObserver: PublishSubject<RemoteAttachmentDownloader.Update>, schemaController: SchemaController) {
        self.viewModel = viewModel
        self.schemaController = schemaController
        self.disposeBag = DisposeBag()
        super.init(nibName: "LookupViewController", bundle: nil)
        self.setupAttachmentObserving(observer: remoteDownloadObserver)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setup()

        self.viewModel.stateObservable
                      .subscribe(with: self, onNext: { `self`, state in
                          self.update(state: state)
                      })
                      .disposed(by: self.disposeBag)

        self.viewModel.process(action: .initialize(self.webView))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.textField.becomeFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.updatePreferredContentSize()
    }

    // MARK: - Actions

    private func update(state: LookupState) {
        switch state.state {
        case .input:
            self.textField.isEnabled = true
        default:
            if self.textField.isFirstResponder {
                self.textField.resignFirstResponder()
            }
            self.textField.isEnabled = false
        }

        switch state.state {
        case .loading, .input:
            self.tableView.isHidden = true
            self.errorLabel.isHidden = true
            self.setupBarButtons(to: state.state)

        case .failed:
            self.errorLabel.isHidden =  false
            self.setupBarButtons(to: state.state)

        case .done(let data):
            let hasAttachment = data.first(where: { !$0.attachments.isEmpty }) != nil

            if !hasAttachment {
                self.navigationController?.presentingViewController?.dismiss(animated: true)
                return
            }

            self.show(data: data) {
                // It takes a little while for the `contentSize` observer notification to come, so all the content is hidden after the notification arrives, so that there is not an empty screen while
                // waiting for it.
                self.errorLabel.isHidden = true
                self.titleLabel.isHidden = true
                self.inputContainer.isHidden = true
                self.topConstraint.constant = 0
                self.setupBarButtons(to: state.state)
            }
        }
    }

    private func show(data: [LookupState.LookupData], completion: @escaping () -> Void) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Row>()
        snapshot.appendSections([0])

        for lookup in data {
            let title: String
            if let _title = lookup.response.fields[FieldKeys.Item.title] {
                title = _title
            } else {
                let _title = lookup.response.fields.first(where: { self.schemaController.baseKey(for: lookup.response.rawType, field: $0.key) == FieldKeys.Item.title })?.value
                title = _title ?? ""
            }
            let itemData = ItemData(type: lookup.response.rawType, title: title)

            snapshot.appendItems([.item(itemData)], toSection: 0)
            snapshot.appendItems(lookup.attachments.map({ .attachment($0.0, .progress(0)) }), toSection: 0)
        }

        self.tableView.isHidden = false
        self.dataSource.apply(snapshot, animatingDifferences: false)

        var isFirstCall = true
        // For some reason, the observer subscription has to be here, doesn't work if it's in `viewDidLoad`.
        self.contentSizeObserver = self.tableView.observe(\.contentSize, options: [.new]) { [weak self] tableView, change in
            guard let `self` = self, let value = change.newValue, value.height != self.tableViewHeight.constant else { return }

            self.tableViewHeight.constant = value.height

            if value.height == self.tableView.frame.height {
                self.tableView.isScrollEnabled = true
                self.contentSizeObserver = nil
            }

            if isFirstCall {
                completion()
            } else {
                isFirstCall = false
            }

            self.updatePreferredContentSize()
        }
    }

    private func process(update: RemoteAttachmentDownloader.Update) {
        guard update.libraryId == self.viewModel.state.libraryId, var snapshot = self.dataSource?.snapshot() else { return }

        var rows = snapshot.itemIdentifiers(inSection: 0)

        guard let index = rows.firstIndex(where: { $0.isAttachment(withKey: update.key, libraryId: update.libraryId) }) else { return }

        snapshot.deleteItems(rows)

        let row = rows[index]
        switch row {
        case .attachment(let attachment, _):
            rows[index] = .attachment(attachment, update.kind)
        case .item: break
        }

        snapshot.appendItems(rows, toSection: 0)

        self.dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func closeAfterUpdateIfNeeded() {
        let activeDownload = self.dataSource.snapshot().itemIdentifiers.first(where: { row in
            switch row {
            case .attachment(_, let update):
                switch update {
                case .progress:
                    return true
                default:
                    return false
                }
            case .item:
                return false
            }
        })

        if activeDownload == nil {
            self.navigationController?.presentingViewController?.dismiss(animated: true)
        }
    }

    private func setupBarButtons(to state: LookupState.State) {
        switch state {
        case .failed, .input:
            let doneItem = UIBarButtonItem(title: L10n.lookUp, style: .done, target: nil, action: nil)
            doneItem.rx.tap.subscribe(onNext: { [weak self] in
                guard let string = self?.textField.text else { return }
                self?.viewModel.process(action: .lookUp(string))
            }).disposed(by: self.disposeBag)
            self.navigationItem.rightBarButtonItem = doneItem

            let cancelItem = UIBarButtonItem(title: L10n.cancel, style: .plain, target: nil, action: nil)
            cancelItem.rx.tap.subscribe(onNext: { [weak self] in
                self?.navigationController?.presentingViewController?.dismiss(animated: true)
            }).disposed(by: self.disposeBag)
            self.navigationItem.leftBarButtonItem = cancelItem

        case .done:
            self.navigationItem.rightBarButtonItem = nil

            let cancelItem = UIBarButtonItem(title: L10n.close, style: .plain, target: nil, action: nil)
            cancelItem.rx.tap.subscribe(onNext: { [weak self] in
                self?.navigationController?.presentingViewController?.dismiss(animated: true)
            }).disposed(by: self.disposeBag)
            self.navigationItem.leftBarButtonItem = cancelItem

        case .loading:
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)

            let cancelItem = UIBarButtonItem(title: L10n.cancel, style: .plain, target: nil, action: nil)
            cancelItem.rx.tap.subscribe(onNext: { [weak self] in
                self?.navigationController?.presentingViewController?.dismiss(animated: true)
            }).disposed(by: self.disposeBag)
            self.navigationItem.leftBarButtonItem = cancelItem
        }
    }

    private func updatePreferredContentSize() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        let size = self.view.systemLayoutSizeFitting(CGSize(width: LookupViewController.width, height: .greatestFiniteMagnitude))
        self.preferredContentSize = CGSize(width: LookupViewController.width, height: size.height - self.view.safeAreaInsets.top)
        self.navigationController?.preferredContentSize = self.preferredContentSize
    }

    private func updateKeyboardSize(_ data: KeyboardData) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        self.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: data.endFrame.height, right: 0)
    }

    // MARK: - Setups

    private func setup() {
        self.titleLabel.text = L10n.Lookup.title
        self.errorLabel.text = L10n.Errors.lookup
        self.setupBarButtons(to: self.viewModel.state.state)
        self.textField.delegate = self

        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        self.phoneBottomConstraint.isActive = isPhone
        self.padBottomConstraint.isActive = !isPhone

        self.setupTableView()
        self.setupKeyboardObserving()
    }

    private func setupTableView() {
        self.tableViewHeight.constant = 0
        self.tableView.register(UINib(nibName: "LookupItemCell", bundle: nil), forCellReuseIdentifier: "Cell")
        self.tableView.isScrollEnabled = false

        self.dataSource = UITableViewDiffableDataSource(tableView: self.tableView, cellProvider: { tableView, indexPath, row in
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var separatorInset = LookupViewController.iconWidth + LookupItemCell.attachmentToLabelOffset

            if let cell = cell as? LookupItemCell {
                switch row {
                case .item(let data):
                    cell.set(title: data.title, type: data.type)
                case .attachment(let attachment, let update):
                    cell.set(title: attachment.title, attachmentType: attachment.type, update: update)
                    separatorInset += LookupItemCell.attachmentOffset
                }
            }

            cell.separatorInset = UIEdgeInsets(top: 0, left: separatorInset, bottom: 0, right: 0)
            cell.selectionStyle = .none

            return cell
        })
    }

    private func setupAttachmentObserving(observer: PublishSubject<RemoteAttachmentDownloader.Update>) {
        observer.observe(on: MainScheduler.instance)
                .subscribe(with: self, onNext: { `self`, update in
                    self.process(update: update)
                    self.closeAfterUpdateIfNeeded()
                })
                .disposed(by: self.disposeBag)
    }

    private func setupKeyboardObserving() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }

        NotificationCenter.default
                          .keyboardWillShow
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.updateKeyboardSize(data)
                              }
                          })
                          .disposed(by: self.disposeBag)

        NotificationCenter.default
                          .keyboardWillHide
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.updateKeyboardSize(data)
                              }
                          })
                          .disposed(by: self.disposeBag)
    }
}

extension LookupViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.viewModel.process(action: .lookUp(textField.text ?? ""))
        return true
    }
}
