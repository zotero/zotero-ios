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
        completionAction = completion
        disposeBag = DisposeBag()
        super.init(nibName: "AnnotationsFilterViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = L10n.Pdf.AnnotationsSidebar.Filter.title

        setupNavigationBar()
        setupColorPicker()
        setSelected(colors: viewModel.state.colors)
        set(tags: viewModel.state.tags, availableTags: viewModel.state.availableTags)

        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { state in
                update(state: state)
            })
            .disposed(by: disposeBag)

        func setupNavigationBar() {
            let closeBarButtonItem = UIBarButtonItem(title: L10n.close, style: .plain, target: nil, action: nil)
            closeBarButtonItem.rx.tap
                .subscribe(onNext: { _ in
                    close()
                })
                .disposed(by: disposeBag)
            navigationItem.leftBarButtonItem = closeBarButtonItem

            setupClearButton(visible: (!viewModel.state.colors.isEmpty || !viewModel.state.tags.isEmpty))

            func close() {
                updateFilter()
                navigationController?.presentingViewController?.dismiss(animated: true)
            }
        }

        func setupColorPicker() {
            viewModel.state.availableColors.forEach { hexColor in
                let circleView = ColorPickerCircleView(hexColor: hexColor)
                circleView.circleSize = CGSize(width: 32, height: 32)
                circleView.selectionLineWidth = 2.5
                circleView.contentInsets = UIEdgeInsets(top: 16, left: 0, bottom: 20, right: 16)
                circleView.backgroundColor = .clear
                circleView.backgroundColor = .white
                circleView.isAccessibilityElement = true
                colorContainer.addArrangedSubview(circleView)

                circleView.tap
                    .observe(on: MainScheduler.instance)
                    .subscribe(onNext: { [weak self] _ in
                        self?.viewModel.process(action: .toggleColor(hexColor))
                    })
                    .disposed(by: disposeBag)
            }
            // Add spacer
            colorContainer.addArrangedSubview(UIView())
        }

        func update(state: AnnotationsFilterState) {
            if state.changes.contains(.colors) {
                setSelected(colors: state.colors)
            }

            if state.changes.contains(.tags) {
                set(tags: state.tags, availableTags: state.availableTags)
            }

            if state.changes.contains(.tags) || state.changes.contains(.colors) {
                setupClearButton(visible: (!state.colors.isEmpty || !state.tags.isEmpty))
            }

            updateFilter()
            updatePreferredContentSize()
        }

        func setSelected(colors: Set<String>) {
            for view in colorContainer.arrangedSubviews {
                guard let pickerView = view as? ColorPickerCircleView else { continue }
                pickerView.isSelected = colors.contains(pickerView.hexColor)
            }
        }

        func set(tags: Set<String>, availableTags: [Tag]) {
            guard !availableTags.isEmpty else {
                tagsContainer.isHidden = true
                return
            }

            tagsContainer.isHidden = false
            let sorted = availableTags.compactMap({ tags.contains($0.name) ? $0 : nil })
            let title = sorted.isEmpty ? L10n.Pdf.AnnotationsSidebar.Filter.tagsPlaceholder : sorted.map({ $0.name }).joined(separator: ", ")
            tagsLabel.text = title
        }

        func setupClearButton(visible: Bool) {
            if !visible {
                if navigationItem.rightBarButtonItem != nil {
                    navigationItem.rightBarButtonItem = nil
                }
                return
            }

            guard navigationItem.rightBarButtonItem == nil else { return }

            let clear = UIBarButtonItem(title: L10n.clear, style: .plain, target: nil, action: nil)
            clear.rx.tap
                .subscribe(onNext: { [weak self] _ in
                    self?.viewModel.process(action: .clear)
                })
                .disposed(by: disposeBag)
            navigationItem.rightBarButtonItem = clear
        }

        func updateFilter() {
            if viewModel.state.colors.isEmpty && viewModel.state.tags.isEmpty {
                completionAction(nil)
            } else {
                let filter = AnnotationsFilter(colors: viewModel.state.colors, tags: viewModel.state.tags)
                completionAction(filter)
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePreferredContentSize()
    }

    // MARK: - Helper Methods
    private func updatePreferredContentSize() {
        let labelSize = tagsLabel.systemLayoutSizeFitting(CGSize(width: Self.width - 40, height: .greatestFiniteMagnitude))
        let size = CGSize(width: Self.width, height: labelSize.height + 88) // 68 for circles, 20 bottom inset
        preferredContentSize = size
        navigationController?.preferredContentSize = size
    }

    // MARK: - Actions
    @IBAction private func showTagPicker() {
        coordinatorDelegate?.showTagPicker(with: viewModel.state.availableTags, selected: viewModel.state.tags) { [weak self] picked in
            self?.viewModel.process(action: .setTags(picked))
        }
    }
}
