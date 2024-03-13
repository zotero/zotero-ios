//
//  AnnotationPopoverViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 13/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift
import CocoaLumberjackSwift

final class AnnotationPopoverViewController: UIViewController {
    let viewModel: ViewModel<AnnotationPopoverActionHandler>
    private let disposeBag: DisposeBag

    @IBOutlet private weak var scrollView: UIScrollView!
    @IBOutlet private weak var containerStackView: UIStackView!
    private weak var header: AnnotationViewHeader!
    private weak var comment: AnnotationViewTextView?
    private weak var colorPicker: ColorPickerStackView!
    private weak var tagsButton: AnnotationViewButton!
    private weak var tags: AnnotationViewText!
    private weak var deleteButton: UIButton!

    weak var coordinatorDelegate: AnnotationPopoverAnnotationCoordinatorDelegate?

    private var commentPlaceholder: String {
        return self.viewModel.state.isEditable ? L10n.Pdf.AnnotationsSidebar.addComment : L10n.Pdf.AnnotationPopover.noComment
    }

    // MARK: - Lifecycle

    init(viewModel: ViewModel<AnnotationPopoverActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()
        super.init(nibName: "AnnotationPopoverViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupViews()
        view.layoutSubviews()

        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(state: state)
            })
            .disposed(by: disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.setNavigationBarHidden(true, animated: animated)
        updatePreferredContentSize()
    }

    deinit {
        DDLogInfo("AnnotationPopoverViewController: deinitialized")
        coordinatorDelegate?.didFinish()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updatePreferredContentSize()
    }

    // MARK: - Actions

    private func updatePreferredContentSize() {
        guard var size = containerStackView?.systemLayoutSizeFitting(CGSize(width: AnnotationPopoverLayout.width, height: .greatestFiniteMagnitude)) else { return }
        size.width = AnnotationPopoverLayout.width
        preferredContentSize = size
        navigationController?.preferredContentSize = size
    }

    private func update(state: AnnotationPopoverState) {
        // Update header
        header.setup(
            type: state.type,
            authorName: state.author,
            pageLabel: state.pageLabel,
            colorHex: state.color,
            shareMenuProvider: { [weak coordinatorDelegate] button in
                coordinatorDelegate?.createShareAnnotationMenu(sender: button)
            },
            isEditable: state.isEditable,
            showsLock: !state.isEditable,
            accessibilityType: .view
        )

        // Update selected color
        colorPicker.setSelected(hexColor: state.color)

        // Update tags
        if !state.tags.isEmpty {
            tags.setup(with: AnnotationView.attributedString(from: state.tags, layout: AnnotationPopoverLayout.annotationLayout))
        }
        tags.isHidden = state.tags.isEmpty
        tagsButton?.isHidden = !state.tags.isEmpty
    }

    private func set(comment: NSAttributedString, heightDidChange: Bool) {
        viewModel.process(action: .setComment(comment))
        guard heightDidChange else { return }
        updatePreferredContentSize()
        scrollToCursorIfNeeded()
    }

    private func name(for color: String, isSelected: Bool) -> String {
        let colorName = AnnotationsConfig.colorNames[color] ?? L10n.unknown
        return !isSelected ? colorName : L10n.Accessibility.Pdf.selected + ": " + colorName
    }

    private func showSettings() {
        // key, color, lineWidth, fontSize, pageLabel, updateSubsequentLabels, highlightText
        coordinatorDelegate?.showEdit(
            state: viewModel.state,
            saveAction: { [weak self] _, _, _, pageLabel, updateSubsequentLabels, highlightText in
                self?.viewModel.process(action: .setProperties(pageLabel: pageLabel, updateSubsequentLabels: updateSubsequentLabels, highlightText: highlightText))
            },
            deleteAction: { [weak self] in
               self?.viewModel.process(action: .delete)
            }
        )
    }

    private func showTagPicker() {
        guard viewModel.state.isEditable else { return }
        let selected = Set(viewModel.state.tags.map({ $0.name }))
        coordinatorDelegate?.showTagPicker(libraryId: viewModel.state.libraryId, selected: selected, picked: { [weak self] tags in
            self?.viewModel.process(action: .setTags(tags))
        })
    }

    private func scrollToCursorIfNeeded() {
        guard let comment, comment.textView.isFirstResponder, let selectedPosition = comment.textView.selectedTextRange?.start else { return }
        let caretRect = comment.textView.caretRect(for: selectedPosition)
        guard (comment.frame.origin.y + caretRect.origin.y) > scrollView.frame.height else { return }
        let rect = CGRect(x: caretRect.origin.x, y: (comment.frame.origin.y + caretRect.origin.y) + 10, width: caretRect.size.width, height: caretRect.size.height)
        scrollView.scrollRectToVisible(rect, animated: true)
    }

    // MARK: - Setups

    private func setupViews() {
        let layout = AnnotationPopoverLayout.annotationLayout

        // Setup header
        let header = AnnotationViewHeader(layout: layout)
        header.setup(
            type: viewModel.state.type,
            authorName: viewModel.state.author,
            pageLabel: viewModel.state.pageLabel,
            colorHex: viewModel.state.color,
            shareMenuProvider: { [weak coordinatorDelegate] button in
                coordinatorDelegate?.createShareAnnotationMenu(sender: button)
            },
            isEditable: viewModel.state.isEditable,
            showsLock: !viewModel.state.isEditable,
            accessibilityType: .view
        )
        header.menuTap
              .subscribe(with: self, onNext: { `self`, _ in
                  self.showSettings()
              })
              .disposed(by: disposeBag)
        if let tap = header.doneTap {
            tap.subscribe(with: self, onNext: { `self`, _ in
                self.presentingViewController?.dismiss(animated: true, completion: nil)
            })
            .disposed(by: disposeBag)
        }
        self.header = header

        containerStackView.addArrangedSubview(header)
        containerStackView.addArrangedSubview(AnnotationViewSeparator())

        // Setup comment
        if viewModel.state.type != .ink {
            let commentView = AnnotationViewTextView(layout: layout, placeholder: commentPlaceholder)
            commentView.setup(text: viewModel.state.comment)
            commentView.isUserInteractionEnabled = viewModel.state.isEditable
            commentView.textObservable
                       .debounce(.milliseconds(500), scheduler: MainScheduler.instance)
                       .subscribe(onNext: { [weak self] data in
                           guard let self, let data else { return }
                           set(comment: data.0, heightDidChange: data.1)
                       })
                       .disposed(by: disposeBag)
            comment = commentView

            containerStackView.addArrangedSubview(commentView)
            containerStackView.addArrangedSubview(AnnotationViewSeparator())
        }

        // Setup color picker
        if viewModel.state.isEditable {
            let colorPickerContainer = UIView()
            colorPickerContainer.backgroundColor = Asset.Colors.defaultCellBackground.color
            colorPickerContainer.accessibilityLabel = L10n.Accessibility.Pdf.colorPicker

            let hexColors = AnnotationsConfig.colors(for: viewModel.state.type)
            let colorPicker = ColorPickerStackView(
                hexColors: hexColors,
                columnsDistribution: .fixed(numberOfColumns: hexColors.count),
                allowsMultipleSelection: false,
                circleBackgroundColor: Asset.Colors.defaultCellBackground.color,
                circleContentInsets: UIEdgeInsets(top: 11, left: 11, bottom: 11, right: 11),
                accessibilityLabelProvider: { [weak self] hexColor, isSelected in
                    self?.name(for: hexColor, isSelected: isSelected)
                },
                hexColorToggled: { [weak self] hexColor in
                    self?.viewModel.process(action: .setColor(hexColor))
                }
            )
            colorPicker.setSelected(hexColor: viewModel.state.color)
            colorPicker.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
            colorPicker.translatesAutoresizingMaskIntoConstraints = false
            self.colorPicker = colorPicker
            colorPickerContainer.addSubview(colorPicker)

            NSLayoutConstraint.activate([
                colorPicker.topAnchor.constraint(equalTo: colorPickerContainer.topAnchor),
                colorPicker.bottomAnchor.constraint(equalTo: colorPickerContainer.bottomAnchor),
                colorPicker.leadingAnchor.constraint(equalTo: colorPickerContainer.leadingAnchor, constant: 5),
                colorPicker.trailingAnchor.constraint(lessThanOrEqualTo: colorPickerContainer.trailingAnchor)
            ])

            containerStackView.addArrangedSubview(colorPickerContainer)
            containerStackView.addArrangedSubview(AnnotationViewSeparator())

            if viewModel.state.type == .ink {
                // Setup line width slider
                let lineView = LineWidthView(title: L10n.Pdf.AnnotationPopover.lineWidth, settings: .lineWidth, contentInsets: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16))
                lineView.value = Float(viewModel.state.lineWidth)
                lineView.valueObservable
                        .subscribe(with: self, onNext: { `self`, value in
                            self.viewModel.process(action: .setLineWidth(CGFloat(value)))
                        })
                        .disposed(by: disposeBag)
                containerStackView.addArrangedSubview(lineView)
                containerStackView.addArrangedSubview(AnnotationViewSeparator())
            }
        }

        // Setup tags
        let tags = AnnotationViewText(layout: layout)
        if !viewModel.state.tags.isEmpty {
            tags.setup(with: AnnotationView.attributedString(from: viewModel.state.tags, layout: layout))
        }
        tags.isHidden = viewModel.state.tags.isEmpty
        tags.isEnabled = viewModel.state.isEditable
        tags.tap
            .subscribe(with: self, onNext: { `self`, _ in
                self.showTagPicker()
            })
            .disposed(by: disposeBag)
        tags.button.accessibilityLabel = L10n.Accessibility.Pdf.tags + ": " + (self.tags?.textLabel.text ?? "")
        tags.textLabel.isAccessibilityElement = false
        self.tags = tags

        containerStackView.addArrangedSubview(tags)

        if viewModel.state.isEditable {
            let tagButton = AnnotationViewButton(layout: layout)
            tagButton.setTitle(L10n.Pdf.AnnotationsSidebar.addTags, for: .normal)
            tagButton.isHidden = !viewModel.state.tags.isEmpty
            tagButton.rx.tap
                     .subscribe(with: self, onNext: { `self`, _ in
                         self.showTagPicker()
                     })
                     .disposed(by: disposeBag)
            tagButton.accessibilityLabel = L10n.Pdf.AnnotationsSidebar.addTags
            tagsButton = tagButton

            containerStackView.addArrangedSubview(tagButton)
            containerStackView.addArrangedSubview(AnnotationViewSeparator())
        }

        if viewModel.state.showsDeleteButton {
            var configuration = UIButton.Configuration.plain()
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: UIColor.red]
            configuration.attributedTitle = AttributedString(L10n.Pdf.AnnotationPopover.delete, attributes: AttributeContainer(attributes))
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 0, bottom: 12, trailing: 0)
            let button = UIButton()
            button.configuration = configuration
            button
                .rx
                .tap
                .subscribe(with: self, onNext: { `self`, _ in
                    self.viewModel.process(action: .delete)
                })
                .disposed(by: disposeBag)
            deleteButton = button

            containerStackView.addArrangedSubview(button)
        }
    }
}

extension AnnotationPopoverViewController: AnnotationPopover {}
