//
//  AnnotationEditViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 27.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

typealias AnnotationEditSaveAction = (_ data: AnnotationEditState.Data, _ updateSubsequentLabels: Bool) -> Void
typealias AnnotationEditDeleteAction = () -> Void

final class AnnotationEditViewController: UIViewController {
    private enum Section {
        case properties, pageLabel, actions, textContent

        func cellId(index: Int, propertyRows: [PropertyRow]) -> String {
            switch self {
            case .properties:
                guard index < propertyRows.count else { return "EmptyCell" }
                switch propertyRows[index] {
                case .colorPicker:
                    return "ColorPickerCell"

                case .lineWidth:
                    return "LineWidthCell"

                case .highlightUnderlineSwitch:
                    return "HighlightUnderlineSwitchCell"

                case .fontSize:
                    return "FontSizeCell"
                }

            case .actions:
                return "ActionCell"

            case .pageLabel:
                return "PageLabelCell"

            case .textContent:
                return "TextContentCell"
            }
        }
    }

    enum PropertyRow {
        case colorPicker, lineWidth, highlightUnderlineSwitch, fontSize

        static func from(type: AnnotationType, isAdditionalSettings: Bool) -> [PropertyRow] {
            switch type {
            case .freeText:
                return isAdditionalSettings ? [] : [.fontSize, .colorPicker]

            case .ink:
                return isAdditionalSettings ? [] : [.colorPicker, .lineWidth]

            case .highlight, .underline:
                return isAdditionalSettings ? [.highlightUnderlineSwitch] : [.colorPicker, .highlightUnderlineSwitch]

            case .image, .note:
                return isAdditionalSettings ? [] : [.colorPicker]
            }
        }
    }

    @IBOutlet private weak var tableView: UITableView!

    private let viewModel: ViewModel<AnnotationEditActionHandler>
    private let sections: [Section]
    private let propertyRows: [PropertyRow]
    private let saveAction: AnnotationEditSaveAction
    private let deleteAction: AnnotationEditDeleteAction
    private let disposeBag: DisposeBag

    weak var coordinatorDelegate: AnnotationEditCoordinatorDelegate?

    init(
        viewModel: ViewModel<AnnotationEditActionHandler>,
        properties: [PropertyRow],
        saveAction: @escaping AnnotationEditSaveAction,
        deleteAction: @escaping AnnotationEditDeleteAction
    ) {
        var sections: [Section] = [.pageLabel, .actions]
        if viewModel.state.isEditable {
            if !properties.isEmpty {
                sections.insert(.properties, at: 0)
            }
            if viewModel.state.type == .highlight || viewModel.state.type == .underline {
                sections.insert(.textContent, at: 0)
            }
        }

        self.viewModel = viewModel
        self.sections = sections
        self.saveAction = saveAction
        self.deleteAction = deleteAction
        propertyRows = properties
        disposeBag = DisposeBag()
        super.init(nibName: "AnnotationEditViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = L10n.Pdf.AnnotationPopover.title
        view.backgroundColor = Asset.Colors.annotationPopoverBackground.color
        setupTableView()
        setupNavigationBar()

        viewModel.stateObservable
            .subscribe(onNext: { [weak self] state in
                self?.update(to: state)
            })
            .disposed(by: disposeBag)

        func setupNavigationBar() {
            navigationItem.hidesBackButton = true

            let cancel = UIBarButtonItem(title: L10n.cancel)
            cancel.tintColor = Asset.Colors.zoteroBlue.color
            cancel.rx.tap
                .subscribe(onNext: { [weak self] in
                    self?.cancel()
                })
                .disposed(by: disposeBag)
            navigationItem.leftBarButtonItem = cancel

            guard viewModel.state.isEditable else { return }

            let save = UIBarButtonItem(title: L10n.save)
            save.tintColor = Asset.Colors.zoteroBlue.color
            if #available(iOS 26.0.0, *) {
                save.style = .prominent
            } else {
                save.style = .done
            }
            save.rx.tap
                .subscribe(onNext: { [weak self] in
                    guard let self else { return }
                    let state = viewModel.state
                    saveAction(state.data, state.updateSubsequentLabels)
                    self.cancel()
                })
                .disposed(by: disposeBag)

            navigationItem.rightBarButtonItem = save
        }

        func setupTableView() {
            tableView.widthAnchor.constraint(equalToConstant: AnnotationPopoverLayout.width).isActive = true
            tableView.delegate = self
            tableView.dataSource = self
            tableView.register(ColorPickerCell.self, forCellReuseIdentifier: Section.properties.cellId(index: 0, propertyRows: [.colorPicker]))
            tableView.register(LineWidthCell.self, forCellReuseIdentifier: Section.properties.cellId(index: 0, propertyRows: [.lineWidth]))
            tableView.register(FontSizeCell.self, forCellReuseIdentifier: Section.properties.cellId(index: 0, propertyRows: [.fontSize]))
            tableView.register(SegmentedControlCell.self, forCellReuseIdentifier: Section.properties.cellId(index: 0, propertyRows: [.highlightUnderlineSwitch]))
            tableView.register(TextContentEditCell.self, forCellReuseIdentifier: Section.textContent.cellId(index: 0, propertyRows: []))
            tableView.register(UITableViewCell.self, forCellReuseIdentifier: Section.actions.cellId(index: 0, propertyRows: []))
            tableView.register(UITableViewCell.self, forCellReuseIdentifier: Section.pageLabel.cellId(index: 0, propertyRows: []))
            tableView.setDefaultSizedHeader()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: true)
        updatePreferredContentSize()
    }

    // MARK: - Actions

    private func update(to state: AnnotationEditState) {
        if state.changes.contains(.color) {
            reload(sections: [.properties, .textContent])
        }
        if state.changes.contains(.pageLabel) {
            reload(sections: [.pageLabel])
        }

        func reload(sections: [Section]) {
            for section in sections {
                guard let index = self.sections.firstIndex(of: section) else { continue }
                tableView.reloadSections(IndexSet(integer: index), with: .none)
            }
        }
    }

    private func updatePreferredContentSize() {
        let sectionCount = sections.count - (sections.contains(.textContent) ? 1 : 0)
        var height: CGFloat = (CGFloat(sectionCount) * 80) + 36 // 80 for 36 spacer and 44 cell height

        if sections.contains(.textContent) {
            let width = AnnotationPopoverLayout.width -
                (
                    (AnnotationPopoverLayout.annotationLayout.horizontalInset * 2) +
                    AnnotationPopoverLayout.annotationLayout.highlightContentLeadingOffset +
                    AnnotationPopoverLayout.annotationLayout.highlightLineWidth
                )
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.minimumLineHeight = AnnotationPopoverLayout.annotationLayout.lineHeight
            paragraphStyle.maximumLineHeight = AnnotationPopoverLayout.annotationLayout.lineHeight
            let attributedText = NSMutableAttributedString(attributedString: viewModel.state.highlightText)
            attributedText.addAttribute(.paragraphStyle, value: paragraphStyle, range: .init(location: 0, length: attributedText.length))
            let boundingRect = attributedText.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)
            height += ceil(boundingRect.height) + 58 // 58 for 22 insets and 36 spacer
        }

        if viewModel.state.type == .ink {
            height += 49 // for line width slider
        }

        let size = CGSize(width: AnnotationPopoverLayout.width, height: height)
        preferredContentSize = size
        navigationController?.preferredContentSize = size
    }

    private func cancel() {
        guard let navigationController else { return }
        if navigationController.viewControllers.count == 1 {
            navigationController.presentingViewController?.dismiss(animated: true, completion: nil)
        } else {
            navigationController.popViewController(animated: true)
        }
    }
}

extension AnnotationEditViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .properties:
            return propertyRows.count

        default:
            return 1
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = sections[indexPath.section]
        let cell = tableView.dequeueReusableCell(withIdentifier: section.cellId(index: indexPath.row, propertyRows: propertyRows), for: indexPath)

        switch section {
        case .properties:
            if let cell = cell as? ColorPickerCell {
                cell.setup(selectedColor: viewModel.state.color, annotationType: viewModel.state.type)
                cell.colorChange.subscribe { [weak viewModel] hex in
                    viewModel?.process(action: .setColor(hex))
                }
                .disposed(by: cell.disposeBag)
            } else if let cell = cell as? LineWidthCell {
                cell.set(value: Float(viewModel.state.lineWidth))
                cell.valueObservable.subscribe(onNext: { [weak viewModel] value in viewModel?.process(action: .setLineWidth(CGFloat(value))) }).disposed(by: cell.disposeBag)
            } else if let cell = cell as? FontSizeCell {
                cell.set(value: viewModel.state.fontSize)
                cell.valueObservable.subscribe(onNext: { [weak viewModel] value in viewModel?.process(action: .setFontSize(value)) }).disposed(by: cell.disposeBag)
            } else if let cell = cell as? SegmentedControlCell {
                let selected = viewModel.state.type == .highlight ? 0 : 1
                cell.setup(selected: selected, segments: [L10n.Pdf.highlight, L10n.Pdf.underline]) { [weak viewModel] selected in
                    viewModel?.process(action: .setAnnotationType(selected == 0 ? .highlight : .underline))
                }
            }

        case .textContent:
            if let cell = cell as? TextContentEditCell {
                cell.setup(with: viewModel.state.highlightText, color: viewModel.state.color)
                cell.attributedTextAndHeightReloadNeededObservable.subscribe { [weak self] attributedText, needsHeightReload in
                    guard let self else { return }
                    viewModel.process(action: .setHighlight(attributedText))
                    if needsHeightReload {
                        updatePreferredContentSize()
                        reloadHeight(controller: self)
                        scrollToHighlightCursor(controller: self)
                    }
                }
                .disposed(by: cell.disposeBag)
            }

        case .pageLabel:
            cell.textLabel?.text = L10n.page + " " + viewModel.state.pageLabel
            if viewModel.state.isEditable {
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.accessoryType = .none
            }

        case .actions:
            cell.textLabel?.text = L10n.Pdf.AnnotationPopover.delete
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.textColor = .red
        }

        return cell

        func reloadHeight(controller: AnnotationEditViewController) {
            controller.tableView.beginUpdates()
            controller.tableView.endUpdates()
        }

        func scrollToHighlightCursor(controller: AnnotationEditViewController) {
            let indexPath = IndexPath(row: 0, section: 0)
            guard let cell = controller.tableView.cellForRow(at: indexPath) as? TextContentEditCell, let cellCaretRect = cell.caretRect else { return }
            let rowRect = controller.tableView.rectForRow(at: indexPath)
            let caretRect = CGRect(x: (rowRect.minX + cellCaretRect.minX), y: (rowRect.minY + cellCaretRect.minY) + 10, width: cellCaretRect.width, height: cellCaretRect.height)
            guard caretRect.maxY > (controller.tableView.contentInset.top + controller.tableView.frame.height) else { return }
            controller.tableView.scrollRectToVisible(caretRect, animated: false)
        }
    }
}

extension AnnotationEditViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch sections[indexPath.section] {
        case .textContent:
            break

        case .properties:
            guard indexPath.row < propertyRows.count else { return }
            switch propertyRows[indexPath.row] {
            case .colorPicker, .lineWidth, .highlightUnderlineSwitch:
                break

            case .fontSize:
                coordinatorDelegate?.showFontSizePicker(picked: { [weak self, weak tableView] newSize in
                    self?.viewModel.process(action: .setFontSize(newSize))
                    tableView?.reloadRows(at: [indexPath], with: .none)
                })
            }

        case .actions:
            deleteAction()

        case .pageLabel:
            guard viewModel.state.isEditable else { return }
            coordinatorDelegate?.showPageLabelEditor(
                label: viewModel.state.pageLabel,
                updateSubsequentPages: viewModel.state.updateSubsequentLabels,
                saveAction: { [weak self] newLabel, shouldUpdateSubsequentPages in
                    self?.viewModel.process(action: .setPageLabel(newLabel, shouldUpdateSubsequentPages))
                }
            )
        }
    }
}

extension AnnotationEditViewController: AnnotationPopover {}
