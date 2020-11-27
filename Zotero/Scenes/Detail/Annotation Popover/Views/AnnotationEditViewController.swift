//
//  AnnotationEditViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 27.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class AnnotationEditViewController: UIViewController {
    private enum Section {
        case colorPicker, pageLabel, actions

        static let sortedAllCases: [Section] = [.colorPicker, .pageLabel, .actions]

        var cellId: String {
            switch self {
            case .colorPicker: return "ColorPickerCell"
            case .actions, .pageLabel: return "BasicCell"
            }
        }
    }

    @IBOutlet private weak var tableView: UITableView!

    private let viewModel: ViewModel<PDFReaderActionHandler>

    init(viewModel: ViewModel<PDFReaderActionHandler>) {
        self.viewModel = viewModel
        super.init(nibName: "AnnotationEditViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = L10n.Pdf.AnnotationPopover.title
        self.setupTableView()
    }

    // MARK: - Actions

    private func confirmDeletion() {
        guard let annotation = self.viewModel.state.selectedAnnotation else { return }

        let controller = UIAlertController(title: L10n.warning, message: L10n.Pdf.AnnotationPopover.deleteConfirm, preferredStyle: .alert)

        controller.addAction(UIAlertAction(title: L10n.yes, style: .destructive, handler: { [weak self] _ in
            self?.viewModel.process(action: .removeAnnotation(annotation))
            self?.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
        }))

        controller.addAction(UIAlertAction(title: L10n.no, style: .cancel, handler: nil))
        self.present(controller, animated: true, completion: nil)
    }

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.register(UINib(nibName: "ColorPickerCell", bundle: nil), forCellReuseIdentifier: Section.colorPicker.cellId)
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: Section.actions.cellId)
        self.tableView.rowHeight = 44
    }
}

extension AnnotationEditViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.sortedAllCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = Section.sortedAllCases[indexPath.section]
        let cell = tableView.dequeueReusableCell(withIdentifier: section.cellId, for: indexPath)

        cell.accessoryType = .none

        switch section {
        case .colorPicker:
            if let cell = cell as? ColorPicker {
                // TODO
            }

        case .pageLabel:
            cell.textLabel?.text = self.viewModel.state.selectedAnnotation?.pageLabel ?? ""
            cell.textLabel?.textAlignment = .left
            cell.accessoryType = .disclosureIndicator
            cell.textLabel?.textColor = .black

        case .actions:
            cell.textLabel?.text = L10n.Pdf.AnnotationPopover.delete
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.textColor = .red
        }

        return cell
    }
}

extension AnnotationEditViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section.sortedAllCases[indexPath.section] {
        case .colorPicker: break
        case .actions:
            self.confirmDeletion()
        case .pageLabel:
            // TODO: show page label input
        break
        }
    }
}
