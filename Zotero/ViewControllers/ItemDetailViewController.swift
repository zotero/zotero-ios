//
//  ItemDetailViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 19/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjack
import PSPDFKit
import PSPDFKitUI
import RxSwift

class ItemDetailViewController: UIViewController {
    // Outlets
    @IBOutlet private weak var tableView: UITableView!
    // Constants
    private let store: ItemDetailStore
    private let disposeBag: DisposeBag
    private let infoSection = 0
    private let attachmentSection = 1

    // MARK: - Lifecycle

    init(store: ItemDetailStore) {
        self.store = store
        self.disposeBag = DisposeBag()
        super.init(nibName: "ItemDetailViewController", bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = self.store.state.value.item.title
        self.setupTableView()

        self.store.state.asObservable()
                        .observeOn(MainScheduler.instance)
                        .subscribe(onNext: { [weak self] state in
                            if state.changes.contains(.data) {
                                self?.tableView.reloadData()
                            }
                            if state.changes.contains(.error) {
                                // TODO: Show error
                            }
                            if state.changes.contains(.download) {
                                self?.updateDownloadState(state.downloadState)
                            }
                        })
                        .disposed(by: self.disposeBag)

        self.store.handle(action: .load)
    }

    // MARK: - Actions

    private func showAttachment(at index: Int) {
        guard let attachments = self.store.state.value.attachments, index < attachments.count else { return }
        self.store.handle(action: .showAttachment(attachments[index]))
    }

    private func updateDownloadState(_ state: ItemDetailState.FileDownload?) {
        guard let state = state else {
            // TODO: - hide UI
            return
        }

        switch state {
        case .progress(let progress):
            // TODO: - show progress ui
            DDLogInfo("ItemDetailViewController: file download progress \(progress)")
            break
        case .downloaded(let file):
            switch file.ext {
            case "pdf":
                self.showPdf(from: file)
            default: break
            }
            DispatchQueue.main.async {
                self.store.handle(action: .attachmentOpened)
            }
        }
    }

    private func showPdf(from file: File) {
        let document = PSPDFDocument(url: file.createUrl())
        let pdfController = PSPDFViewController(document: document)
        let navigationController = UINavigationController(rootViewController: pdfController)
        self.present(navigationController, animated: true, completion: nil)
    }

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.register(UINib(nibName: ItemFieldCell.nibName, bundle: nil),
                                forCellReuseIdentifier: ItemFieldCell.nibName)
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "AttachmentCell")
    }
}

extension ItemDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case self.infoSection:
            return self.store.state.value.fields.count
        case self.attachmentSection:
            return self.store.state.value.attachments?.count ?? 0
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case self.infoSection:
            return "Info"
        case self.attachmentSection:
            return "Attachments"
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = indexPath.section == self.infoSection ? ItemFieldCell.nibName : "AttachmentCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)

        if let cell = cell as? ItemFieldCell {
            if indexPath.row < self.store.state.value.fields.count {
                let field = self.store.state.value.fields[indexPath.row]
                cell.setup(with: field)
            }
        } else {
            if let attachments = self.store.state.value.attachments, indexPath.row < attachments.count {
                cell.textLabel?.text = attachments[indexPath.row].title
            }
        }

        return cell
    }
}

extension ItemDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch indexPath.section {
        case self.attachmentSection:
            self.showAttachment(at: indexPath.row)
        default: break
        }
    }
}

extension ItemDetailField: ItemFieldCellModel {
    var title: String {
        return self.name
    }
}
