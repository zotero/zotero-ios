//
//  AnnotationViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 13/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift
import CocoaLumberjackSwift

final class AnnotationViewController: UIViewController {
    let annotationKey: PDFReaderState.AnnotationKey?
    private let viewModel: ViewModel<PDFReaderActionHandler>
    private unowned let attributedStringConverter: HtmlAttributedStringConverter
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
        let canEdit = self.viewModel.state.selectedAnnotation?.editability(currentUserId: self.viewModel.state.userId, library: self.viewModel.state.library) == .editable
        return canEdit ? L10n.Pdf.AnnotationsSidebar.addComment : L10n.Pdf.AnnotationPopover.noComment
    }

    // MARK: - Lifecycle

    init(viewModel: ViewModel<PDFReaderActionHandler>, attributedStringConverter: HtmlAttributedStringConverter) {
        self.viewModel = viewModel
        self.annotationKey = viewModel.state.selectedAnnotationKey
        self.attributedStringConverter = attributedStringConverter
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupViews()
        self.view.layoutSubviews()

        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(state: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.navigationController?.setNavigationBarHidden(true, animated: animated)
        self.updatePreferredContentSize()
    }

    deinit {
        DDLogInfo("AnnotationViewController: deinitialized")
        self.coordinatorDelegate?.didFinish()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        self.updatePreferredContentSize()
    }

    // MARK: - Actions

    private func updatePreferredContentSize() {
        guard var size = self.containerStackView?.systemLayoutSizeFitting(CGSize(width: AnnotationPopoverLayout.width, height: .greatestFiniteMagnitude)) else { return }
        size.width = AnnotationPopoverLayout.width
        self.preferredContentSize = size
        self.navigationController?.preferredContentSize = size
    }

    private func update(state: PDFReaderState) {
        guard state.changes.contains(.annotations), let annotation = state.selectedAnnotation else { return }

        // Update header
        let editability = annotation.editability(currentUserId: state.userId, library: state.library)
        self.header.setup(
            type: annotation.type,
            authorName: annotation.author(displayName: state.displayName, username: state.username),
            pageLabel: annotation.pageLabel,
            colorHex: annotation.color,
            libraryId: state.library.identifier,
            shareMenuProvider: { [weak self] button in
                self?.createShareAnnotationMenu(sender: button)
            },
            isEditable: (editability == .editable),
            showsLock: (editability != .editable),
            accessibilityType: .view
        )

        // Update selected color
        colorPicker.setSelected(hexColor: annotation.color)

        // Update tags
        if !annotation.tags.isEmpty {
            self.tags.setup(with: AnnotationView.attributedString(from: annotation.tags, layout: AnnotationPopoverLayout.annotationLayout))
        }
        self.tags.isHidden = annotation.tags.isEmpty
        self.tagsButton?.isHidden = !annotation.tags.isEmpty
    }

    private func name(for color: String, isSelected: Bool) -> String {
        let colorName = AnnotationsConfig.colorNames[color] ?? L10n.unknown
        return !isSelected ? colorName : L10n.Accessibility.Pdf.selected + ": " + colorName
    }

    @objc private func deleteAnnotation() {
        guard let key = self.viewModel.state.selectedAnnotationKey else { return }
        self.viewModel.process(action: .removeAnnotation(key))
    }
    
    private func createShareAnnotationMenu(sender: UIButton) -> UIMenu? {
        coordinatorDelegate?.createShareAnnotationMenu(sender: sender)
    }

    private func showSettings() {
        guard let annotation = self.viewModel.state.selectedAnnotation else { return }
<<<<<<< HEAD
        let key = annotation.readerKey
=======
>>>>>>> 74e1d1e3 (Font size picker added, annotation popup updated with font options)
        self.coordinatorDelegate?.showEdit(
            annotation: annotation,
            userId: self.viewModel.state.userId,
            library: self.viewModel.state.library,
<<<<<<< HEAD
            saveAction: { [weak self] color, lineWidth, pageLabel, updateSubsequentLabels, highlightText in
=======
            saveAction: { [weak self] key, color, lineWidth, fontSize, pageLabel, updateSubsequentLabels, highlightText in
>>>>>>> 74e1d1e3 (Font size picker added, annotation popup updated with font options)
                self?.viewModel.process(
                    action: .updateAnnotationProperties(
                        key: key.key,
                        color: color,
                        lineWidth: lineWidth,
<<<<<<< HEAD
=======
                        fontSize: fontSize,
>>>>>>> 74e1d1e3 (Font size picker added, annotation popup updated with font options)
                        pageLabel: pageLabel,
                        updateSubsequentLabels: updateSubsequentLabels,
                        highlightText: highlightText
                    )
                )
            },
<<<<<<< HEAD
            deleteAction: { [weak self] in
               self?.viewModel.process(action: .removeAnnotation(key))
=======
            deleteAction: { [weak self] key in
                self?.viewModel.process(action: .removeAnnotation(key))
>>>>>>> 74e1d1e3 (Font size picker added, annotation popup updated with font options)
            }
        )
    }

    private func set(color: String) {
        guard let annotation = self.viewModel.state.selectedAnnotation else { return }
        self.viewModel.process(action: .setColor(key: annotation.key, color: color))
    }

    private func showTagPicker() {
        guard let annotation = self.viewModel.state.selectedAnnotation, annotation.isAuthor(currentUserId: self.viewModel.state.userId) else { return }

        let selected = Set(annotation.tags.map({ $0.name }))
        self.coordinatorDelegate?.showTagPicker(libraryId: self.viewModel.state.library.identifier, selected: selected, picked: { [weak self] tags in
            self?.viewModel.process(action: .setTags(key: annotation.key, tags: tags))
        })
    }

    private func scrollToCursorIfNeeded() {
        guard let commentView = self.comment, commentView.textView.isFirstResponder, let selectedPosition = commentView.textView.selectedTextRange?.start else { return }
        let caretRect = commentView.textView.caretRect(for: selectedPosition)
        guard (commentView.frame.origin.y + caretRect.origin.y) > self.scrollView.frame.height else { return }

        let rect = CGRect(x: caretRect.origin.x, y: (commentView.frame.origin.y + caretRect.origin.y) + 10, width: caretRect.size.width, height: caretRect.size.height)
        self.scrollView.scrollRectToVisible(rect, animated: true)
    }

    // MARK: - Setups

    private func setupViews() {
        guard let annotation = self.viewModel.state.selectedAnnotation else { return }

        let layout = AnnotationPopoverLayout.annotationLayout

        // Setup header
        let header = AnnotationViewHeader(layout: layout)
        let editability = annotation.editability(currentUserId: self.viewModel.state.userId, library: self.viewModel.state.library)
        header.setup(
            type: annotation.type,
            authorName: annotation.author(displayName: self.viewModel.state.displayName, username: self.viewModel.state.username),
            pageLabel: annotation.pageLabel,
            colorHex: annotation.color,
            libraryId: self.viewModel.state.library.identifier,
            shareMenuProvider: { [weak self] button in
                self?.createShareAnnotationMenu(sender: button)
            },
            isEditable: (editability == .editable),
            showsLock: (editability != .editable),
            accessibilityType: .view
        )
        header.menuTap
              .subscribe(with: self, onNext: { `self`, _ in
                  self.showSettings()
              })
              .disposed(by: self.disposeBag)
        if let tap = header.doneTap {
            tap.subscribe(with: self, onNext: { `self`, _ in
                self.presentingViewController?.dismiss(animated: true, completion: nil)
            })
            .disposed(by: self.disposeBag)
        }
        self.header = header

        self.containerStackView.addArrangedSubview(header)
        self.containerStackView.addArrangedSubview(AnnotationViewSeparator())

        // Setup comment
        if annotation.type != .ink {
            let commentView = AnnotationViewTextView(layout: layout, placeholder: self.commentPlaceholder)
            let comment = AnnotationView.attributedString(from: self.attributedStringConverter.convert(text: annotation.comment, baseAttributes: [.font: layout.font]), layout: layout)
            commentView.setup(text: comment)
            commentView.isUserInteractionEnabled = editability == .editable
            commentView.textObservable
                .debounce(.milliseconds(500), scheduler: MainScheduler.instance)
                .subscribe(onNext: { [weak self] data in
                    guard let self, let (text, needsHeightReload) = data else { return }
                    viewModel.process(action: .setComment(key: annotation.key, comment: text))
                    if needsHeightReload {
                        updatePreferredContentSize()
                        scrollToCursorIfNeeded()
                    }
                })
                .disposed(by: disposeBag)
            self.comment = commentView

            self.containerStackView.addArrangedSubview(commentView)
            self.containerStackView.addArrangedSubview(AnnotationViewSeparator())
        }

        if editability == .editable {
            // Setup color picker
            let colorPickerContainer = UIView()
            colorPickerContainer.backgroundColor = Asset.Colors.defaultCellBackground.color
            colorPickerContainer.accessibilityLabel = L10n.Accessibility.Pdf.colorPicker

            let hexColors = AnnotationsConfig.colors(for: annotation.type)
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
                    self?.set(color: hexColor)
                }
            )
            colorPicker.setSelected(hexColor: viewModel.state.selectedAnnotation?.color)
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

            self.containerStackView.addArrangedSubview(colorPickerContainer)
            self.containerStackView.addArrangedSubview(AnnotationViewSeparator())

            switch annotation.type {
            case .ink:
                // Setup line width slider
                let lineView = LineWidthView(title: L10n.Pdf.AnnotationPopover.lineWidth, settings: .lineWidth, contentInsets: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16))
                lineView.value = Float(annotation.lineWidth ?? 0)
                lineView.valueObservable
                        .subscribe(with: self, onNext: { `self`, value in
                            self.viewModel.process(action: .setLineWidth(key: annotation.key, width: CGFloat(value)))
                        })
                        .disposed(by: self.disposeBag)
                self.containerStackView.addArrangedSubview(lineView)
                self.containerStackView.addArrangedSubview(AnnotationViewSeparator())

            case .freeText:
                // Setup font size picker
                let lineView = FontSizeView(contentInsets: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16), stepperEnabled: true)
                lineView.value = annotation.fontSize ?? 0
                lineView.tapObservable
                    .subscribe(with: self, onNext: { `self`, _ in
                        self.coordinatorDelegate?.showFontSizePicker(picked: { [weak self, weak lineView] newSize in
                            self?.viewModel.process(action: .setFontSize(key: annotation.key, size: newSize))
                            lineView?.value = newSize
                        })
                    })
                    .disposed(by: self.disposeBag)
                lineView.valueObservable
                    .subscribe(with: self, onNext: { `self`, value in
                        self.viewModel.process(action: .setFontSize(key: annotation.key, size: value))
                    })
                    .disposed(by: self.disposeBag)
                self.containerStackView.addArrangedSubview(lineView)
                self.containerStackView.addArrangedSubview(AnnotationViewSeparator())

            default:
                break
            }
        }

        // Setup tags
        let tags = AnnotationViewText(layout: layout)
        if !annotation.tags.isEmpty {
            tags.setup(with: AnnotationView.attributedString(from: annotation.tags, layout: layout))
        }
        tags.isHidden = annotation.tags.isEmpty
        tags.isEnabled = editability == .editable
        tags.tap
            .subscribe(with: self, onNext: { `self`, _ in
                self.showTagPicker()
            })
            .disposed(by: self.disposeBag)
        tags.button.accessibilityLabel = L10n.Accessibility.Pdf.tags + ": " + (self.tags?.textLabel.text ?? "")
        tags.textLabel.isAccessibilityElement = false
        self.tags = tags

        self.containerStackView.addArrangedSubview(tags)

        if editability == .editable {
            let tagButton = AnnotationViewButton(layout: layout)
            tagButton.setTitle(L10n.Pdf.AnnotationsSidebar.addTags, for: .normal)
            tagButton.isHidden = !annotation.tags.isEmpty
            tagButton.rx.tap
                     .subscribe(with: self, onNext: { `self`, _ in
                         self.showTagPicker()
                     })
                     .disposed(by: self.disposeBag)
            tagButton.accessibilityLabel = L10n.Pdf.AnnotationsSidebar.addTags
            self.tagsButton = tagButton

            self.containerStackView.addArrangedSubview(tagButton)
            self.containerStackView.addArrangedSubview(AnnotationViewSeparator())
        }

        if editability != .notEditable {
            var configuration = UIButton.Configuration.plain()
            configuration.attributedTitle = AttributedString(L10n.Pdf.AnnotationPopover.delete, attributes: AttributeContainer([.font: UIFont.preferredFont(forTextStyle: .body)]))
            configuration.baseForegroundColor = .red
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)
            let button = UIButton()
            button.configuration = configuration
            button.addTarget(self, action: #selector(AnnotationViewController.deleteAnnotation), for: .touchUpInside)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            self.deleteButton = button

            self.containerStackView.addArrangedSubview(button)
        }
    }
}

extension AnnotationViewController: AnnotationPopover {}
