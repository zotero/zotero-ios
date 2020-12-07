//
//  AnnotationPageLabelViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 01.12.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

typealias AnnotationPageLabelSaveAction = (String, Bool) -> Void

class AnnotationPageLabelViewController: UIViewController {
    enum Section {
        case labelInput
        case switches

        static let sortedAllCases: [Section] = [.labelInput, .switches]

        var cellId: String {
            switch self {
            case .labelInput: return "InputCell"
            case .switches: return "SwitchCell"
            }
        }
    }

    @IBOutlet private weak var tableView: UITableView!

    private let viewModel: ViewModel<AnnotationPageLabelActionHandler>
    private let saveAction: AnnotationPageLabelSaveAction
    private let disposeBag: DisposeBag

    init(viewModel: ViewModel<AnnotationPageLabelActionHandler>, saveAction: @escaping AnnotationPageLabelSaveAction) {
        self.viewModel = viewModel
        self.saveAction = saveAction
        self.disposeBag = DisposeBag()
        super.init(nibName: "AnnotationPageLabelViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = L10n.Pdf.AnnotationPopover.pageLabelTitle
        self.setupNavigationItems()
        self.setupTableView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.preferredContentSize = AnnotationPopoverLayout.pageEditPreferredSize
        self.navigationController?.preferredContentSize = AnnotationPopoverLayout.pageEditPreferredSize
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.focusPageLabel()
    }

    // MARK: - Actions

    private func focusPageLabel() {
        guard let section = Section.sortedAllCases.firstIndex(of: .labelInput) else { return }
        let indexPath = IndexPath(row: 0, section: section)
        self.tableView.cellForRow(at: indexPath)?.becomeFirstResponder()
    }

    // MARK: - Setup

    private func setupTableView() {
        self.tableView.dataSource = self
        self.tableView.rowHeight = 44
        self.tableView.register(UINib(nibName: "TextFieldCell", bundle: nil), forCellReuseIdentifier: Section.labelInput.cellId)
        self.tableView.register(UINib(nibName: "SwitchCell", bundle: nil), forCellReuseIdentifier: Section.switches.cellId)
    }

    private func setupNavigationItems() {
        self.navigationItem.hidesBackButton = true

        let cancel = UIBarButtonItem(title: L10n.cancel, style: .plain, target: nil, action: nil)
        cancel.rx.tap
            .subscribe(onNext: { [weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            })
            .disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = cancel

        let save = UIBarButtonItem(title: L10n.save, style: .done, target: nil, action: nil)
        save.rx.tap
            .subscribe(onNext: { [weak self] _ in
                guard let `self` = self else { return }
                self.saveAction(self.viewModel.state.label, self.viewModel.state.updateSubsequentPages)
                self.navigationController?.popViewController(animated: true)
            })
            .disposed(by: self.disposeBag)
        self.navigationItem.rightBarButtonItem = save
    }
}

extension AnnotationPageLabelViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.sortedAllCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = Section.sortedAllCases[indexPath.section]
        let cell = tableView.dequeueReusableCell(withIdentifier: section.cellId, for: indexPath)

        if let cell = cell as? TextFieldCell {
            cell.setup(with: self.viewModel.state.label)
            cell.textObservable
                .subscribe(onNext: { [weak self] text in
                    self?.viewModel.process(action: .setLabel(text))
                })
                .disposed(by: cell.disposeBag)
        } else if let cell = cell as? SwitchCell {
            cell.setup(with: L10n.Pdf.AnnotationPopover.updateSubsequentPages, isOn: self.viewModel.state.updateSubsequentPages)
            cell.switchObservable
                .subscribe(onNext: { [weak self] isOn in
                    self?.viewModel.process(action: .setUpdateSubsequentLabels(isOn))
                })
                .disposed(by: self.disposeBag)
        }

        return cell
    }
}
