//
//  AnnotationsFilterViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 01.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class AnnotationsFilterViewController: UIViewController {
    @IBOutlet private weak var colorContainer: UIStackView!
    @IBOutlet private weak var tagsContainer: UIView!
    @IBOutlet private weak var tagsLabel: UILabel!

    private static let width: CGFloat = 300
    private let viewModel: ViewModel<AnnotationsFilterActionHandler>
    private let completionAction: (AnnotationsFilter?) -> Void
    private let disposeBag: DisposeBag

    weak var coordinatorDelegate: AnnotationsFilterPopoverToAnnotationsFilterCoordinatorDelegate?

    init(viewModel: ViewModel<AnnotationsFilterActionHandler>, completion: @escaping (AnnotationsFilter?) -> Void) {
        self.viewModel = viewModel
        self.completionAction = completion
        self.disposeBag = DisposeBag()
        super.init(nibName: "AnnotationsFilterViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = L10n.Pdf.AnnotationsSidebar.Filter.title

        self.setupNavigationBar()
        self.setupColorPicker()
        self.setSelected(colors: self.viewModel.state.colors)
        self.set(tags: self.viewModel.state.tags, availableTags: self.viewModel.state.availableTags)

        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(state: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.updatePreferredContentSize()
    }

    // MARK: - Actions

    private func update(state: AnnotationsFilterState) {
        if state.changes.contains(.colors) {
            self.setSelected(colors: state.colors)
        }

        if state.changes.contains(.tags) {
            self.set(tags: state.tags, availableTags: state.availableTags)
        }

        if state.changes.contains(.tags) || state.changes.contains(.colors) {
            self.setupClearButton(visible: (!state.colors.isEmpty || !state.tags.isEmpty))
        }

        if UIDevice.current.userInterfaceIdiom == .pad {
            self.updateFilter()
            self.updatePreferredContentSize()
        }
    }

    private func updatePreferredContentSize() {
        let labelSize = self.tagsLabel.systemLayoutSizeFitting(CGSize(width: AnnotationsFilterViewController.width - 40, height: .greatestFiniteMagnitude))
        let size = CGSize(width: AnnotationsFilterViewController.width, height: labelSize.height + 88) // 68 for circles, 20 bottom inset
        self.preferredContentSize = size
        self.navigationController?.preferredContentSize = size
    }

    private func setSelected(colors: Set<String>) {
        for view in self.colorContainer.arrangedSubviews {
            guard let pickerView = view as? ColorPickerCircleView else { continue }
            pickerView.isSelected = colors.contains(pickerView.hexColor)
        }
    }

    private func set(tags: Set<String>, availableTags: [Tag]) {
        if availableTags.isEmpty {
            self.tagsContainer.isHidden = true
            return
        }

        self.tagsContainer.isHidden = false
        let sorted = availableTags.compactMap({ tags.contains($0.name) ? $0 : nil })
        let title = sorted.isEmpty ? L10n.Pdf.AnnotationsSidebar.Filter.tagsPlaceholder : sorted.map({ $0.name }).joined(separator: ", ")
        self.tagsLabel.text = title
    }

    private func close() {
        if UIDevice.current.userInterfaceIdiom == .phone {
            self.updateFilter()
        }
        self.navigationController?.presentingViewController?.dismiss(animated: true)
    }

    private func updateFilter() {
        if self.viewModel.state.colors.isEmpty && self.viewModel.state.tags.isEmpty {
            self.completionAction(nil)
        } else {
            let filter = AnnotationsFilter(colors: self.viewModel.state.colors, tags: self.viewModel.state.tags)
            self.completionAction(filter)
        }
    }

    @IBAction private func showTagPicker() {
        self.coordinatorDelegate?.showTagPicker(with: self.viewModel.state.availableTags, selected: self.viewModel.state.tags, completed: { [weak self] picked in
            self?.viewModel.process(action: .setTags(picked))
        })
    }

    // MARK: - Setups

    private func setupColorPicker() {
        self.viewModel.state.availableColors.forEach { hexColor in
            let circleView = ColorPickerCircleView(hexColor: hexColor)
            circleView.circleSize = CGSize(width: 32, height: 32)
            circleView.selectionLineWidth = 2.5
            circleView.contentInsets = UIEdgeInsets(top: 16, left: 0, bottom: 20, right: 16)
            circleView.backgroundColor = .clear
            circleView.backgroundColor = .white
            circleView.isAccessibilityElement = true
            self.colorContainer.addArrangedSubview(circleView)

            circleView.tap.observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] _ in
                              self?.viewModel.process(action: .toggleColor(hexColor))
                          })
                          .disposed(by: self.disposeBag)
        }
        // Add spacer
        self.colorContainer.addArrangedSubview(UIView())
    }

    private func setupNavigationBar() {
        if UIDevice.current.userInterfaceIdiom == .phone {
            let close = UIBarButtonItem(title: L10n.close, style: .plain, target: nil, action: nil)
            close.rx.tap.subscribe(onNext: { [weak self] _ in
                self?.close()
            })
            .disposed(by: self.disposeBag)
            self.navigationItem.leftBarButtonItem = close
        }

        self.setupClearButton(visible: (!self.viewModel.state.colors.isEmpty || !self.viewModel.state.tags.isEmpty))
    }

    private func setupClearButton(visible: Bool) {
        if !visible {
            if self.navigationItem.rightBarButtonItem != nil {
                self.navigationItem.rightBarButtonItem = nil
            }
            return
        }

        guard self.navigationItem.rightBarButtonItem == nil else { return }

        let clear = UIBarButtonItem(title: L10n.clear, style: .plain, target: nil, action: nil)
        clear.rx.tap.subscribe(onNext: { [weak self] _ in
            self?.viewModel.process(action: .clear)
        })
        .disposed(by: self.disposeBag)
        self.navigationItem.rightBarButtonItem = clear
    }
}
