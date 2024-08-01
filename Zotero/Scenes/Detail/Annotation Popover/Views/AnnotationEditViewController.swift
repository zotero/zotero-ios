//
//  AnnotationEditViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 27.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

// key, color, lineWidth, fontSize, pageLabel, updateSubsequentLabels, highlightText
typealias AnnotationEditSaveAction = (String, CGFloat, UInt, String, Bool, String) -> Void
typealias AnnotationEditDeleteAction = () -> Void

final class AnnotationEditViewController: UIViewController {
    private enum Section {
        case properties, pageLabel, actions, textContent, fontSize

        func cellId(index: Int) -> String {
            switch self {
            case .properties: return index == 0 ? "ColorPickerCell" : "LineWidthCell"
            case .actions: return "ActionCell"
            case .pageLabel: return "PageLabelCell"
            case .textContent: return "TextContentCell"
            case .fontSize: return "FontSizeCell"
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

    init(viewModel: ViewModel<AnnotationEditActionHandler>, includeColorPicker: Bool, includeFontPicker: Bool, saveAction: @escaping AnnotationEditSaveAction, deleteAction: @escaping AnnotationEditDeleteAction) {
        var sections: [Section] = [.pageLabel, .actions]
        if viewModel.state.isEditable {
            if includeColorPicker {
                sections.insert(.properties, at: 0)
            }
            if includeFontPicker {
                sections.insert(.fontSize, at: 0)
            }
            if viewModel.state.type == .highlight || viewModel.state.type == .underline {
                sections.insert(.textContent, at: 0)
            }
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
        self.view.backgroundColor = Asset.Colors.annotationPopoverBackground.color
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
        self.navigationController?.setNavigationBarHidden(false, animated: true)
        self.updatePreferredContentSize()
    }

    // MARK: - Actions

    private func update(to state: AnnotationEditState) {
        if state.changes.contains(.color) {
            self.reload(sections: [.properties, .textContent])
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

    private func reloadHeight() {
        self.tableView.beginUpdates()
        self.tableView.endUpdates()
    }

    private func scrollToHighlightCursor() {
        let indexPath = IndexPath(row: 0, section: 0)

        guard let cell = self.tableView.cellForRow(at: indexPath) as? TextContentEditCell, let cellCaretRect = cell.caretRect else { return }

        let rowRect = self.tableView.rectForRow(at: indexPath)
        let caretRect = CGRect(x: (rowRect.minX + cellCaretRect.minX), y: (rowRect.minY + cellCaretRect.minY) + 10, width: cellCaretRect.width, height: cellCaretRect.height)

        guard caretRect.maxY > (self.tableView.contentInset.top + self.tableView.frame.height) else { return }

        self.tableView.scrollRectToVisible(caretRect, animated: false)
    }

    private func updatePreferredContentSize() {
        let sectionCount = self.sections.count - (self.sections.contains(.textContent) ? 1 : 0)
        var height: CGFloat = (CGFloat(sectionCount) * 80) + 36 // 80 for 36 spacer and 44 cell height

        if sections.contains(.textContent) {
            let width = AnnotationPopoverLayout.width - ((AnnotationPopoverLayout.annotationLayout.horizontalInset * 2) +
                                                          AnnotationPopoverLayout.annotationLayout.highlightContentLeadingOffset +
                                                          AnnotationPopoverLayout.annotationLayout.highlightLineWidth)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.minimumLineHeight = AnnotationPopoverLayout.annotationLayout.lineHeight
            paragraphStyle.maximumLineHeight = AnnotationPopoverLayout.annotationLayout.lineHeight
            let attributedText = NSAttributedString(string: self.viewModel.state.highlightText, attributes: [.font: AnnotationPopoverLayout.annotationLayout.font, .paragraphStyle: paragraphStyle])
            let boundingRect = attributedText.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)
            height += ceil(boundingRect.height) + 58 // 58 for 22 insets and 36 spacer
        }

        if self.viewModel.state.type == .ink {
            height += 49 // for line width slider
        }

        let size = CGSize(width: AnnotationPopoverLayout.width, height: height)
        self.preferredContentSize = size
        self.navigationController?.preferredContentSize = size
    }

    private func cancel() {
        guard let navigationController = self.navigationController else { return }
        if navigationController.viewControllers.count == 1 {
            self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
        } else {
            self.navigationController?.popViewController(animated: true)
        }
    }

    // MARK: - Setups

    private func setupNavigationBar() {
        self.navigationItem.hidesBackButton = true

        let cancel = UIBarButtonItem(title: L10n.cancel, style: .plain, target: nil, action: nil)
        cancel.rx.tap.subscribe(onNext: { [weak self] in
            self?.cancel()
        }).disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = cancel

        guard self.viewModel.state.isEditable else { return }

        let save = UIBarButtonItem(title: L10n.save, style: .done, target: nil, action: nil)
        save.rx.tap
               .subscribe(onNext: { [weak self] in
                   guard let self else { return }
                   let state = viewModel.state
                   saveAction(state.color, state.lineWidth, state.fontSize, state.pageLabel, state.updateSubsequentLabels, state.highlightText)
                   self.cancel()
               })
               .disposed(by: self.disposeBag)

        self.navigationItem.rightBarButtonItem = save
    }

    private func setupTableView() {
        self.tableView.widthAnchor.constraint(equalToConstant: AnnotationPopoverLayout.width).isActive = true
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.register(ColorPickerCell.self, forCellReuseIdentifier: Section.properties.cellId(index: 0))
        self.tableView.register(LineWidthCell.self, forCellReuseIdentifier: Section.properties.cellId(index: 1))
        self.tableView.register(TextContentEditCell.self, forCellReuseIdentifier: Section.textContent.cellId(index: 0))
        self.tableView.register(FontSizeCell.self, forCellReuseIdentifier: Section.fontSize.cellId(index: 0))
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: Section.actions.cellId(index: 0))
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: Section.pageLabel.cellId(index: 0))
        self.tableView.setDefaultSizedHeader()
    }
}

extension AnnotationEditViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch self.sections[section] {
        case .properties:
            return self.viewModel.state.type == .ink ? 2 : 1

        default:
            return 1
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = self.sections[indexPath.section]
        let cell = tableView.dequeueReusableCell(withIdentifier: section.cellId(index: indexPath.row), for: indexPath)

        switch section {
        case .properties:
            if let cell = cell as? ColorPickerCell {
                cell.setup(selectedColor: self.viewModel.state.color, annotationType: self.viewModel.state.type)
                cell.colorChange.subscribe(onNext: { hex in self.viewModel.process(action: .setColor(hex)) }).disposed(by: cell.disposeBag)
            } else if let cell = cell as? LineWidthCell {
                cell.set(value: Float(self.viewModel.state.lineWidth))
                cell.valueObservable.subscribe(onNext: { value in self.viewModel.process(action: .setLineWidth(CGFloat(value))) }).disposed(by: cell.disposeBag)
            }

        case .textContent:
            if let cell = cell as? TextContentEditCell {
                cell.setup(with: self.viewModel.state.highlightText, color: self.viewModel.state.color)
                cell.textAndHeightReloadNeededObservable.subscribe { [weak self] text, needsHeightReload in
                    guard let self else { return }
                    viewModel.process(action: .setHighlight(text))
                    if needsHeightReload {
                        updatePreferredContentSize()
                        reloadHeight()
                        scrollToHighlightCursor()
                    }
                }
                .disposed(by: cell.disposeBag)
            }

        case .fontSize:
            if let cell = cell as? FontSizeCell {
                cell.set(value: self.viewModel.state.fontSize)
                cell.valueObservable.subscribe(onNext: { value in self.viewModel.process(action: .setFontSize(value)) }).disposed(by: cell.disposeBag)
            }

        case .pageLabel:
            cell.textLabel?.text = L10n.page + " " + self.viewModel.state.pageLabel
            if self.isEditing {
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
    }
}

extension AnnotationEditViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch self.sections[indexPath.section] {
        case .properties, .textContent: break

        case .actions:
            self.deleteAction()

        case .pageLabel:
            guard self.viewModel.state.isEditable else { return }

            self.coordinatorDelegate?.showPageLabelEditor(
                label: self.viewModel.state.pageLabel,
                updateSubsequentPages: self.viewModel.state.updateSubsequentLabels,
                saveAction: { [weak self] newLabel, shouldUpdateSubsequentPages in
                    self?.viewModel.process(action: .setPageLabel(newLabel, shouldUpdateSubsequentPages))
                }
            )

        case .fontSize:
            self.coordinatorDelegate?.showFontSizePicker(picked: { [weak self, weak tableView] newSize in
                self?.viewModel.process(action: .setFontSize(newSize))
                tableView?.reloadRows(at: [indexPath], with: .none)
            })
        }
    }
}

extension AnnotationEditViewController: AnnotationPopover {}
