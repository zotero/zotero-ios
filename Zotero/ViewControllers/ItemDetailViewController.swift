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
                            self?.process(state: state)
                        })
                        .disposed(by: self.disposeBag)

        self.store.handle(action: .load)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.splitViewController?.presentsWithGesture = false
    }

    // MARK: - Actions

    private func process(state: ItemDetailStore.StoreState) {
        if state.changes.contains(.data) {
            self.tableView.reloadData()
        }
        if state.changes.contains(.download) {
            self.updateDownloadState(state.downloadState)
        }
        if let error = state.error {
            // TODO: Show error
        }
    }

    private func showAttachment(at index: Int) {
        guard let attachments = self.store.state.value.attachments, index < attachments.count else { return }
        self.store.handle(action: .showAttachment(attachments[index]))
    }

    private func updateDownloadState(_ state: ItemDetailStore.StoreState.FileDownload?) {
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

    private func cellId(for row: Int, section: ItemDetailStore.StoreState.Section) -> String {
        switch section {
        case .title, .fields, .abstract:
            return self.cellId(for: section)
        case .tags, .related, .notes, .attachments:
            if row == 0 {
                return ItemSpecialTitleCell.nibName
            }
            return self.cellId(for: section)
        }
    }

    private func cellId(for section: ItemDetailStore.StoreState.Section) -> String {
        switch section {
        case .title:
            return ItemTitleCell.nibName
        case .fields:
            return ItemFieldCell.nibName
        case .abstract:
            return ItemAbstractCell.nibName
        case .tags, .related, .notes, .attachments:
            return ItemSpecialCell.nibName
        }
    }

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.dataSource = self
        self.tableView.delegate = self
        ItemDetailStore.StoreState.Section.allCases.forEach { section in
            let identifier = self.cellId(for: section)
            self.tableView.register(UINib(nibName: identifier, bundle: nil),
                                    forCellReuseIdentifier: identifier)
        }
        self.tableView.register(UINib(nibName: ItemSpecialTitleCell.nibName, bundle: nil),
                                forCellReuseIdentifier: ItemSpecialTitleCell.nibName)
        self.tableView.tableFooterView = UIView()
    }
}

extension ItemDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.store.state.value.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let state = self.store.state.value
        switch self.store.state.value.sections[section] {
        case .title, .abstract:
            return 1
        case .fields:
            return state.fields.count
        case .attachments:
            return state.attachments.flatMap({ $0.count + 1 }) ?? 0
        case .notes:
            return state.notes.flatMap({ $0.count + 1 }) ?? 0
        case .tags:
            return state.tags.flatMap({ $0.count + 1 }) ?? 0
        case .related:
            return 0 // TODO - change when related are added
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch self.store.state.value.sections[section] {
        case .title, .fields, .abstract:
            return 0
        case .attachments, .notes, .tags, .related:
            return 10
        }
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        guard section < (self.store.state.value.sections.count - 1) else { return 0 }

        switch self.store.state.value.sections[section] {
        case .title, .fields:
            return 0
        case .attachments, .notes, .tags, .abstract, .related:
            return 10
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = self.store.state.value.sections[indexPath.section]
        let cellId = self.cellId(for: indexPath.row, section: section)
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath)

        if let cell = cell as? ItemTitleCell {
            cell.setup(with: self.store.state.value.item.title)
        } else if let cell = cell as? ItemAbstractCell {
            cell.setup(with: (self.store.state.value.abstract ?? ""))
        } else if let cell = cell as? ItemFieldCell {
            cell.setup(with: self.store.state.value.fields[indexPath.row])
        } else if let cell = cell as? ItemSpecialTitleCell {
            switch section {
            case .attachments:
                cell.setup(with: "Attachments")
            case .notes:
                cell.setup(with: "Notes")
            case .tags:
                cell.setup(with: "Tags")
            case .related: break
            default: break
            }
        } else if let cell = cell as? ItemSpecialCell {
            let index = indexPath.row - 1
            let model: ItemSpecialCellModel?
            switch section {
            case .attachments:
                model = self.store.state.value.attachments?[index]
            case .notes:
                model = self.store.state.value.notes?[index]
            case .tags:
                model = self.store.state.value.tags?[index]
            case .related:
                model = nil
            default:
                model = nil
            }

            if let model = model {
                cell.setup(with: model)
            }
        }

        return cell
    }
}

extension ItemDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch self.store.state.value.sections[indexPath.section] {
        case .attachments:
            if indexPath.row > 0 {
                self.showAttachment(at: (indexPath.row - 1))
            }
        default: break
        }
    }
}

extension ItemDetailStore.StoreState.Field: ItemFieldCellModel {
    var title: String {
        return self.name
    }
}

extension RTag: ItemSpecialCellModel {
    var title: String {
        return self.name
    }

    var specialIcon: UIImage? {
        return UIImage(named: "icon_cell_tag")?.withRenderingMode(.alwaysTemplate)
    }
}

extension RItem: ItemSpecialCellModel {
    var specialIcon: UIImage? {
        switch self.type {
        case .attachment:
            return UIImage(named: "icon_cell_attachment")?.withRenderingMode(.alwaysTemplate)
        case .note:
            return UIImage(named: "icon_cell_note")?.withRenderingMode(.alwaysTemplate)
        default:
            return nil
        }
    }
}
