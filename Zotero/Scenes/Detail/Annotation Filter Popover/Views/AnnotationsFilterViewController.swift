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
    private static let width: CGFloat = 300
    private static let horizontalInset: CGFloat = 20
    private static let bottomInset: CGFloat = 20
    private let viewModel: ViewModel<AnnotationsFilterActionHandler>
    private let completionAction: (AnnotationsFilter?) -> Void
    private let disposeBag: DisposeBag

    private var colorPickerHeight: CGFloat = 0
    private weak var container: UIStackView?
    private weak var colorPicker: ColorPickerStackView?
    private weak var tagsContainer: UIStackView?
    private weak var tagsLabel: UILabel?

    weak var coordinatorDelegate: AnnotationsFilterPopoverToAnnotationsFilterCoordinatorDelegate?

    init(viewModel: ViewModel<AnnotationsFilterActionHandler>, completion: @escaping (AnnotationsFilter?) -> Void) {
        self.viewModel = viewModel
        completionAction = completion
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let view = UIView()
        view.backgroundColor = Asset.Colors.annotationPopoverBackground.color
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = L10n.Pdf.AnnotationsSidebar.Filter.title

        setupView()
        setupNavigationBar()
        colorPicker?.setSelected(hexColors: Array(viewModel.state.colors))
        set(tags: viewModel.state.tags, availableTags: viewModel.state.availableTags)

        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { state in
                update(state: state)
            })
            .disposed(by: disposeBag)

        func setupView() {
            let circleSize: CGFloat = 32
            let circleOffset: CGFloat = 8
            let circleContentInsets = UIEdgeInsets(top: 16, left: 0, bottom: 16, right: 16)
            let colorPicker = ColorPickerStackView(
                hexColors: viewModel.state.availableColors,
                columnsDistribution: UIDevice.current.userInterfaceIdiom == .pad ? .fixed(numberOfColumns: 4) : .fitInWidth(width: UIScreen.main.bounds.width - (2 * Self.horizontalInset)),
                allowsMultipleSelection: true,
                circleBackgroundColor: Asset.Colors.annotationPopoverBackground.color,
                circleSize: circleSize,
                circleOffset: circleOffset,
                circleSelectionLineWidth: 2.5,
                circleContentInsets: circleContentInsets,
                trailingSpacerViewProvider: {
                    let spacerView = UIView()
                    spacerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
                    return spacerView
                },
                hexColorToggled: { [weak self] hexColor in
                    self?.viewModel.process(action: .toggleColor(hexColor))
                }
            )
            colorPicker.accessibilityLabel = L10n.Accessibility.Pdf.colorPicker
            self.colorPicker = colorPicker

            let colorRowsCount = CGFloat(colorPicker.arrangedSubviews.count)
            colorPickerHeight = (circleContentInsets.top + circleSize + circleContentInsets.bottom) * colorRowsCount + circleOffset * (colorRowsCount - 1)

            let tagsLabel = UILabel()
            tagsLabel.font = .preferredFont(forTextStyle: .body)
            tagsLabel.numberOfLines = 0
            tagsLabel.setContentHuggingPriority(.required, for: .horizontal)
            self.tagsLabel = tagsLabel

            let tagsView = UIView(frame: CGRect(x: 0, y: 0, width: 280, height: 128))
            tagsView.backgroundColor = .clear

            let imageView = UIImageView(image: UIImage(systemName: "chevron.right"))
            imageView.setContentHuggingPriority(.required, for: .horizontal)
            imageView.tintColor = .systemGray3

            let tagsContainer = UIStackView(arrangedSubviews: [tagsLabel, tagsView, imageView])
            tagsContainer.alignment = .center
            tagsContainer.spacing = 20
            tagsContainer.axis = .horizontal
            self.tagsContainer = tagsContainer

            let recognizer = UITapGestureRecognizer()
            recognizer.rx.event
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] _ in
                    guard let self else { return }
                    coordinatorDelegate?.showTagPicker(with: viewModel.state.availableTags, selected: viewModel.state.tags) { [weak self] picked in
                        self?.viewModel.process(action: .setTags(picked))
                    }
                })
                .disposed(by: disposeBag)
            tagsContainer.addGestureRecognizer(recognizer)

            let container = UIStackView(arrangedSubviews: [colorPicker, tagsContainer])
            container.setContentHuggingPriority(.required, for: .vertical)
            container.spacing = 0
            container.axis = .vertical
            container.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(container)
            self.container = container

            NSLayoutConstraint.activate([
                container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                container.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Self.horizontalInset),
                container.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -Self.horizontalInset)
            ])
        }

        func setupNavigationBar() {
            let primaryAction = UIAction(title: L10n.close) { [weak self] _ in
                guard let self else { return }
                updateFilter()
                navigationController?.presentingViewController?.dismiss(animated: true)
            }
            let closeBarButtonItem: UIBarButtonItem
            if #available(iOS 26.0.0, *) {
                closeBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: primaryAction)
            } else {
                closeBarButtonItem = UIBarButtonItem(primaryAction: primaryAction)
            }
            navigationItem.leftBarButtonItem = closeBarButtonItem

            setupClearButton(visible: (!viewModel.state.colors.isEmpty || !viewModel.state.tags.isEmpty))

            func close() {
                updateFilter()
                navigationController?.presentingViewController?.dismiss(animated: true)
            }
        }

        func update(state: AnnotationsFilterState) {
            if state.changes.contains(.colors) {
                colorPicker?.setSelected(hexColors: Array(state.colors))
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

        func set(tags: Set<String>, availableTags: [Tag]) {
            guard !availableTags.isEmpty else {
                tagsContainer?.isHidden = true
                return
            }

            tagsContainer?.isHidden = false
            let sorted = availableTags.compactMap({ tags.contains($0.name) ? $0 : nil })
            let title = sorted.isEmpty ? L10n.Pdf.AnnotationsSidebar.Filter.tagsPlaceholder : sorted.map({ $0.name }).joined(separator: ", ")
            tagsLabel?.text = title
        }

        func setupClearButton(visible: Bool) {
            if !visible {
                if navigationItem.rightBarButtonItem != nil {
                    navigationItem.rightBarButtonItem = nil
                }
                return
            }

            guard navigationItem.rightBarButtonItem == nil else { return }

            let primaryAction = UIAction(title: L10n.clear) { [weak viewModel] _ in
                viewModel?.process(action: .clear)
            }
            let clear = UIBarButtonItem(primaryAction: primaryAction)
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
        guard let tagsLabel else { return }
        let labelSize = tagsLabel.systemLayoutSizeFitting(CGSize(width: Self.width - Self.horizontalInset * 2, height: .greatestFiniteMagnitude))
        let size = CGSize(width: Self.width, height: colorPickerHeight + labelSize.height + Self.bottomInset)
        preferredContentSize = size
        navigationController?.preferredContentSize = size
    }
}
