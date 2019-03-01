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
    fileprivate enum Section {
        case info, attachments, notes, tags
    }

    // Outlets
    @IBOutlet private weak var tableView: UITableView!
    // Constants
    private let store: ItemDetailStore
    private let disposeBag: DisposeBag
    // Variables
    private var sections: [Section] = []

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
                                var sections: [Section] = [.info]
                                if state.attachments?.isEmpty == false {
                                    sections.append(.attachments)
                                }
                                if state.notes?.isEmpty == false {
                                    sections.append(.notes)
                                }
                                if state.tags?.isEmpty == false {
                                    sections.append(.tags)
                                }
                                self?.sections = sections
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
        return self.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch self.sections[section] {
        case .info:
            return self.store.state.value.fields.count
        case .attachments:
            return self.store.state.value.attachments?.count ?? 0
        case .notes:
            return self.store.state.value.notes?.count ?? 0
        case .tags:
            return self.store.state.value.tags?.count ?? 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch self.sections[section] {
        case .info:
            return "Info"
        case .attachments:
            return "Attachments"
        case .notes:
            return "Notes"
        case .tags:
            return "Tags"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = self.sections[indexPath.section]
        let identifier = section == .info ? ItemFieldCell.nibName : "AttachmentCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)

        switch section {
        case .info:
            if let cell = cell as? ItemFieldCell {
                if indexPath.row < self.store.state.value.fields.count {
                    let field = self.store.state.value.fields[indexPath.row]
                    cell.setup(with: field)
                }
            }
        case .attachments:
            if let attachments = self.store.state.value.attachments, indexPath.row < attachments.count {
                cell.textLabel?.text = attachments[indexPath.row].title
                cell.textLabel?.numberOfLines = 1
                cell.textLabel?.textColor = .black
            }
        case .notes:
            if let notes = self.store.state.value.notes, indexPath.row < notes.count {
                cell.textLabel?.text = notes[indexPath.row].title
                cell.textLabel?.numberOfLines = 0
                cell.textLabel?.textColor = .black
            }
        case .tags:
            if let tags = self.store.state.value.tags, indexPath.row < tags.count {
                cell.textLabel?.text = tags[indexPath.row].name
                cell.textLabel?.textColor = tags[indexPath.row].uiColor ?? .black
            }
        }

        return cell
    }
}

extension ItemDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch self.sections[indexPath.section] {
        case .attachments:
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
