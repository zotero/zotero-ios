//
//  AnnotationEditViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 27.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

typealias AnnotationEditSaveAction = (Annotation) -> Void
typealias AnnotationEditDeleteAction = (Annotation) -> Void

class AnnotationEditViewController: UIViewController {
    private enum Section {
        case colorPicker, pageLabel, actions, highlight

        var cellId: String {
            switch self {
            case .colorPicker: return "ColorPickerCell"
            case .actions: return "ActionCell"
            case .pageLabel: return "PageLabelCell"
            case .highlight: return "HighlightCell"
            }
        }
    }

    @IBOutlet private weak var tableView: UITableView!

    private let viewModel: ViewModel<AnnotationEditActionHandler>
    private let sections: [Section]
    private let saveAction: AnnotationEditSaveAction
    private let deleteAction: AnnotationEditDeleteAction
    private let disposeBag: DisposeBag

    weak var coordinatorDelegate: AnnotationEditCoordinatorDelegate?

    init(viewModel: ViewModel<AnnotationEditActionHandler>, saveAction: @escaping AnnotationEditSaveAction, deleteAction: @escaping AnnotationEditDeleteAction) {
        var sections: [Section] = [.colorPicker, .pageLabel, .actions]
        if viewModel.state.annotation.type == .highlight {
            sections.insert(.highlight, at: 0)
        }

        self.viewModel = viewModel
        self.sections = sections
        self.saveAction = saveAction
        self.deleteAction = deleteAction
        self.disposeBag = DisposeBag()
        super.init(nibName: "AnnotationEditViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = L10n.Pdf.AnnotationPopover.title
        self.setupTableView()
        self.setupNavigationBar()

        self.viewModel.stateObservable
                      .subscribe(onNext: { [weak self] state in
                          self?.update(to: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.view.layoutIfNeeded()
        self.tableView.reloadData()
        self.updatePreferredContentSize()
    }

    // MARK: - Actions

    private func update(to state: AnnotationEditState) {
        if state.changes.contains(.color) {
            self.reload(sections: [.colorPicker, .highlight])
        }
        if state.changes.contains(.pageLabel) {
            self.reload(sections: [.pageLabel])
        }
    }

    private func reload(sections: [Section]) {
        for section in sections {
            guard let index = self.sections.firstIndex(of: section) else { continue }
            self.tableView.reloadSections(IndexSet(integer: index), with: .none)
        }
    }

    private func confirmDeletion() {
        let controller = UIAlertController(title: L10n.warning, message: L10n.Pdf.AnnotationPopover.deleteConfirm, preferredStyle: .alert)

        controller.addAction(UIAlertAction(title: L10n.yes, style: .destructive, handler: { [weak self] _ in
            guard let `self` = self else { return }
            self.deleteAction(self.viewModel.state.annotation)
            self.coordinatorDelegate?.dismiss()
        }))

        controller.addAction(UIAlertAction(title: L10n.no, style: .cancel, handler: nil))
        self.present(controller, animated: true, completion: nil)
    }

    private func reloadHeight() {
        self.tableView.beginUpdates()
        self.tableView.endUpdates()
    }

    private func focusHighlightCell() {
        let indexPath = IndexPath(row: 0, section: 0)

        let cellBottom = self.tableView.rectForRow(at: indexPath).maxY - self.tableView.contentOffset.y
        let tableViewBottom = self.tableView.superview!.bounds.maxY - self.tableView.contentInset.bottom

        guard cellBottom > tableViewBottom else { return }

        self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
    }

    private func updatePreferredContentSize() {
        let size = self.tableView.contentSize
        self.preferredContentSize = size
        self.navigationController?.preferredContentSize = size
    }

    // MARK: - Setups

    private func setupNavigationBar() {
        self.navigationItem.hidesBackButton = true

        let cancel = UIBarButtonItem(title: L10n.cancel, style: .plain, target: nil, action: nil)
        cancel.rx.tap.subscribe(onNext: { [weak self] in self?.coordinatorDelegate?.back() }).disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = cancel

        let save = UIBarButtonItem(title: L10n.save, style: .done, target: nil, action: nil)
        save.rx.tap
               .subscribe(onNext: { [weak self] in
                   guard let `self` = self else { return }
                   self.saveAction(self.viewModel.state.annotation)
                   self.coordinatorDelegate?.back()
               })
               .disposed(by: self.disposeBag)

        self.navigationItem.rightBarButtonItem = save
    }

    private func setupTableView() {
        self.tableView.widthAnchor.constraint(equalToConstant: AnnotationPopoverLayout.width).isActive = true
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.register(UINib(nibName: "ColorPickerCell", bundle: nil), forCellReuseIdentifier: Section.colorPicker.cellId)
        self.tableView.register(UINib(nibName: "HighlightEditCell", bundle: nil), forCellReuseIdentifier: Section.highlight.cellId)
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: Section.actions.cellId)
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: Section.pageLabel.cellId)
    }
}

extension AnnotationEditViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = self.sections[indexPath.section]
        let cell = tableView.dequeueReusableCell(withIdentifier: section.cellId, for: indexPath)

        switch section {
        case .colorPicker:
            if let cell = cell as? ColorPickerCell {
                cell.setup(selectedColor: self.viewModel.state.annotation.color)
                cell.colorChange.subscribe(onNext: { hex in self.viewModel.process(action: .setColor(hex)) }).disposed(by: cell.disposeBag)
            }

        case .highlight:
            if let cell = cell as? HighlightEditCell {
                cell.setup(with: (self.viewModel.state.annotation.text ?? ""), color: self.viewModel.state.annotation.color)
                cell.textObservable
                    .subscribe(onNext: { [weak self] text, needsHeightReload in
                        if needsHeightReload {
                            self?.reloadHeight()
                            self?.updatePreferredContentSize()
                            self?.focusHighlightCell()
                        }
                        self?.viewModel.process(action: .setHighlight(text.string))
                    })
                    .disposed(by: self.disposeBag)
            }

        case .pageLabel:
            cell.textLabel?.text = self.viewModel.state.annotation.pageLabel
            cell.accessoryType = .disclosureIndicator

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

        switch self.sections[indexPath.section] {
        case .colorPicker, .highlight: break
        case .actions:
            self.confirmDeletion()
        case .pageLabel:
            self.coordinatorDelegate?.showPageLabelEditor(label: self.viewModel.state.annotation.pageLabel,
                                                          updateSubsequentPages: self.viewModel.state.updateSubsequentLabels,
                                                          saveAction: { [weak self] newLabel, shouldUpdateSubsequentPages in
                self?.viewModel.process(action: .setPageLabel(newLabel, shouldUpdateSubsequentPages))
            })
        break
        }
    }
}
