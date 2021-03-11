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

final class AnnotationPageLabelViewController: UIViewController {
    enum Section {
        case labelInput
        case switches

        static let sortedAllCases: [Section] = [.labelInput]

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
        self.view.backgroundColor = Asset.Colors.annotationPopoverBackground.color
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.saveAction(self.viewModel.state.label, self.viewModel.state.updateSubsequentPages)
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
