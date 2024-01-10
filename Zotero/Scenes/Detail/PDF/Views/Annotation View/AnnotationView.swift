//
//  AnnotationView.swift
//  Zotero
//
//  Created by Michal Rentka on 13/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class AnnotationView: UIView {
    enum Kind {
        case cell, popover
    }

    enum Action {
        case tags
        case options(UIButton?)
        case reloadHeight
        case setComment(NSAttributedString)
        case setCommentActive(Bool)
        case done
    }

    enum AccessibilityType {
        case cell
        case view
    }

    struct Comment {
        let attributedString: NSAttributedString?
        let isActive: Bool
    }

    private let layout: AnnotationViewLayout
    let actionPublisher: PublishSubject<AnnotationView.Action>

    private var header: AnnotationViewHeader!
    private var topSeparator: UIView!
    private var highlightContent: AnnotationViewHighlightContent?
    private var imageContent: AnnotationViewImageContent?
    private var commentTextView: AnnotationViewTextView!
    private var bottomSeparator: UIView!
    private var tagsButton: AnnotationViewButton!
    private var tags: AnnotationViewText!
    private var scrollView: UIScrollView?
    private var scrollViewContent: UIView?
    private(set) var disposeBag: CompositeDisposable?

    var tagString: String? {
        return self.tags.textLabel.text
    }

    // MARK: - Lifecycle

    init(layout: AnnotationViewLayout, commentPlaceholder: String) {
        self.layout = layout
        self.actionPublisher = PublishSubject()

        super.init(frame: CGRect())

        self.backgroundColor = layout.backgroundColor
        self.translatesAutoresizingMaskIntoConstraints = false
        self.setupView(commentPlaceholder: commentPlaceholder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions

    @discardableResult
    override func resignFirstResponder() -> Bool {
        self.commentTextView.resignFirstResponder()
    }

    func updatePreview(image: UIImage?) {
        guard let imageContent = self.imageContent, !imageContent.isHidden else { return }
        imageContent.setup(with: image)
    }

    private func scrollToBottomIfNeeded() {
        guard let scrollView = self.scrollView, let contentView = self.scrollViewContent, contentView.frame.height > scrollView.frame.height else { return }
        let yOffset = scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom
        scrollView.setContentOffset(CGPoint(x: 0, y: yOffset), animated: true)
    }

    // MARK: - Setups

    /// Setups up annotation view with given annotation and additional data.
    /// - parameter annotation: Annotation to show in view.
    /// - parameter comment: Comment to show. If nil, comment field is not shown.
    /// - parameter preview: Preview image to show. If nil, no image is shown.
    /// - parameter selected: If true, selected state style is applied.
    /// - parameter availableWidth: Available width for view.
    /// - parameter library: Library of given annotation
    /// - parameter pdfAnnotationsCoordinatorDelegate: Delegate for getting share menu.
    /// - parameter state: State required for setting up share menu.
    func setup(with annotation: Annotation, comment: Comment?, preview: UIImage?, selected: Bool, availableWidth: CGFloat, library: Library, currentUserId: Int, displayName: String, username: String,
               boundingBoxConverter: AnnotationBoundingBoxConverter, pdfAnnotationsCoordinatorDelegate: PdfAnnotationsCoordinatorDelegate, state: PDFReaderState) {
        let editability = annotation.editability(currentUserId: currentUserId, library: library)
        let color = UIColor(hex: annotation.color)
        let canEdit = editability == .editable && selected

        self.header.setup(
            with: annotation,
            libraryId: library.identifier,
            shareMenuProvider: { button in
                pdfAnnotationsCoordinatorDelegate.createShareAnnotationMenu(state: state, annotation: annotation, sender: button)
            },
            isEditable: (editability != .notEditable && selected),
            showsLock: editability != .editable,
            accessibilityType: .cell,
            displayName: displayName,
            username: username
        )
        self.setupContent(for: annotation, preview: preview, color: color, canEdit: canEdit, selected: selected, availableWidth: availableWidth, accessibilityType: .cell, boundingBoxConverter: boundingBoxConverter)
        self.setup(comment: comment, canEdit: canEdit)
        self.setupTags(for: annotation, canEdit: canEdit, accessibilityEnabled: selected)
        self.setupObserving()

        let commentButtonIsHidden = self.commentTextView.isHidden
        let highlightContentIsHidden = self.highlightContent?.isHidden ?? true
        let imageContentIsHidden = self.imageContent?.isHidden ?? true

        // Top separator is hidden only if there is only header visible and nothing else
        self.topSeparator.isHidden = self.commentTextView.isHidden && commentButtonIsHidden && highlightContentIsHidden && imageContentIsHidden && self.tags.isHidden && self.tagsButton.isHidden
        // Bottom separator is visible, when tags are showing (either actual tags or tags button) and there is something visible above them (other than header, either content or comments/comments button)
        self.bottomSeparator.isHidden = (self.tags.isHidden && self.tagsButton.isHidden) || (self.commentTextView.isHidden && commentButtonIsHidden && highlightContentIsHidden && imageContentIsHidden)
    }

    private func setupContent(for annotation: Annotation, preview: UIImage?, color: UIColor, canEdit: Bool, selected: Bool, availableWidth: CGFloat, accessibilityType: AccessibilityType,
                              boundingBoxConverter: AnnotationBoundingBoxConverter) {
        guard let highlightContent = self.highlightContent, let imageContent = self.imageContent else { return }

        highlightContent.isUserInteractionEnabled = false
        highlightContent.isHidden = annotation.type != .highlight
        imageContent.isHidden = annotation.type != .image && annotation.type != .ink

        switch annotation.type {
        case .note: break

        case .highlight:
            let bottomInset = self.inset(from: self.layout.highlightLineVerticalInsets, hasComment: !annotation.comment.isEmpty, selected: selected, canEdit: canEdit)
            highlightContent.setup(with: color, text: (annotation.text ?? ""), bottomInset: bottomInset, accessibilityType: accessibilityType)

        case .image, .ink:
            let size = annotation.previewBoundingBox(boundingBoxConverter: boundingBoxConverter).size
            let maxWidth = availableWidth - (self.layout.horizontalInset * 2)
            var maxHeight = ceil((size.height / size.width) * maxWidth)
            if maxHeight.isNaN || maxHeight.isInfinite {
                maxHeight = maxWidth * 2
            } else {
                maxHeight = min((maxWidth * 2), maxHeight)
            }
            let bottomInset = self.inset(from: self.layout.verticalSpacerHeight, hasComment: !annotation.comment.isEmpty, selected: selected, canEdit: canEdit)
            imageContent.setup(with: preview, height: maxHeight, bottomInset: bottomInset)
        }
    }

    private func inset(from baseInset: CGFloat, hasComment: Bool, selected: Bool, canEdit: Bool) -> CGFloat {
        if hasComment {
            return baseInset / 2
        }
        return (selected && canEdit) ? 0 : baseInset
    }

    /// Setups comment input. If comment is nil or comment can't be edited and there is no assigned comment string, the input is hidden. Otherwise the input either acts as text view or button.
    /// - parameter comment: Comment to show.
    /// - parameter canEdit: Indicates whether comment can be edited by the user.
    private func setup(comment: Comment?, canEdit: Bool) {
        let isEmptyComment = (comment?.attributedString?.string ?? "").isEmpty
        guard let comment = comment, !isEmptyComment || canEdit else {
            self.commentTextView.isHidden = true
            return
        }

        self.commentTextView.isHidden = false
        self.commentTextView.isUserInteractionEnabled = canEdit

        // If comment is empty and not active, the input acts as a button.
        if isEmptyComment && !comment.isActive {
            self.commentTextView.set(placeholderColor: Asset.Colors.zoteroBlue.color)
            self.commentTextView.setup(text: nil)
            return
        }

        // If there is any comment or the comment is active, the input acts as a text view with a placeholder.
        let attributedString = comment.attributedString.flatMap({ AnnotationView.attributedString(from: $0, layout: self.layout) })
        self.commentTextView.set(placeholderColor: .placeholderText)
        self.commentTextView.setup(text: attributedString)

        if canEdit && comment.isActive {
            self.commentTextView.becomeFirstResponder()
        }
    }

    private func setupTags(for annotation: Annotation, canEdit: Bool, accessibilityEnabled: Bool) {
        guard !annotation.tags.isEmpty else {
            self.tagsButton.isHidden = !canEdit
            self.tagsButton.accessibilityLabel = L10n.Pdf.AnnotationsSidebar.addTags
            self.tagsButton.isAccessibilityElement = true
            self.tags.isHidden = true
            return
        }

        let tagString = AnnotationView.attributedString(from: annotation.tags, layout: self.layout)
        self.tags.setup(with: tagString)

        self.tagsButton.isHidden = true
        self.tags.isHidden = false
        self.tags.isUserInteractionEnabled = canEdit
        self.tags.button.isAccessibilityElement = true
        self.tags.button.accessibilityLabel = L10n.Accessibility.Pdf.tags + ": " + tagString.string

        if accessibilityEnabled {
            self.tags.button.accessibilityTraits = .button
            self.tags.button.accessibilityHint = L10n.Accessibility.Pdf.tagsHint
        } else {
            self.tags.button.accessibilityTraits = .staticText
            self.tags.button.accessibilityHint = nil
        }
    }

    @DisposeBag.DisposableBuilder
    private func buildDisposables() -> [Disposable] {
        self.commentTextView.didBecomeActive.subscribe(onNext: { [weak self] _ in
            self?.actionPublisher.on(.next(.setCommentActive(true)))
        })
        self.commentTextView.textObservable
            .debounce(.milliseconds(500), scheduler: MainScheduler.instance)
            .subscribe(onNext: { [weak self] text, needsHeightReload in
                self?.actionPublisher.on(.next(.setComment(text)))
                if needsHeightReload {
                    self?.actionPublisher.on(.next(.reloadHeight))
                    self?.scrollToBottomIfNeeded()
                }
            })
        self.tags.tap.flatMap({ _ in Observable.just(Action.tags) }).bind(to: self.actionPublisher)
        self.tagsButton.rx.tap.flatMap({ Observable.just(Action.tags) }).bind(to: self.actionPublisher)
        self.header.menuTap.flatMap({ Observable.just(Action.options($0)) }).bind(to: self.actionPublisher)
    }
    
    private func setupObserving() {
        var disposables: [Disposable] = buildDisposables()
        if let doneTap = self.header.doneTap {
            disposables.append(doneTap.flatMap({ Observable.just(Action.done) }).bind(to: self.actionPublisher))
        }
        disposeBag = CompositeDisposable(disposables: disposables)
    }

    private func setupView(commentPlaceholder: String) {
        self.header = AnnotationViewHeader(layout: self.layout)
        self.topSeparator = AnnotationViewSeparator()
        self.commentTextView = AnnotationViewTextView(layout: self.layout, placeholder: commentPlaceholder)
        self.commentTextView.accessibilityLabelPrefix = L10n.Accessibility.Pdf.comment + ": "
        self.bottomSeparator = AnnotationViewSeparator()
        self.tagsButton = AnnotationViewButton(layout: self.layout)
        self.tagsButton.setTitle(L10n.Pdf.AnnotationsSidebar.addTags, for: .normal)
        self.tags = AnnotationViewText(layout: self.layout)

        if self.layout.showsContent {
            self.highlightContent = AnnotationViewHighlightContent(layout: self.layout)
            self.imageContent = AnnotationViewImageContent(layout: self.layout)
        }

        let view = self.layout.scrollableBody ? self.createScrollableBodyView() : self.createStaticBodyView()
        self.addSubview(view)

        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: self.topAnchor),
            view.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])
    }

    private func createStaticBodyView() -> UIView {
        var views: [UIView] = [self.header, self.topSeparator]
        if self.layout.showsContent {
            if let highlightContent = self.highlightContent {
                views.append(highlightContent)
            }
            if let imageContent = self.imageContent {
                views.append(imageContent)
            }
        }
        views.append(contentsOf: [self.commentTextView, self.bottomSeparator, self.tagsButton, self.tags])
        return self.createStackView(with: views)
    }

    private func createScrollableBodyView() -> UIView {
        let stackView = self.createStackView(with: [self.commentTextView, self.bottomSeparator, self.tagsButton, self.tags])
        self.scrollViewContent = stackView

        let scrollView = UIScrollView()
        scrollView.addSubview(stackView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView = scrollView

        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(self.header)
        view.addSubview(self.topSeparator)
        view.addSubview(scrollView)

        let height = stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        height.priority = .defaultHigh

        NSLayoutConstraint.activate([
            // Vertical
            self.header.topAnchor.constraint(equalTo: view.topAnchor),
            self.header.bottomAnchor.constraint(equalTo: self.topSeparator.topAnchor),
            self.topSeparator.bottomAnchor.constraint(equalTo: scrollView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            height,
            // Horizontal
            self.header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            self.header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            self.topSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            self.topSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        return view
    }

    private func createStackView(with children: [UIView]) -> UIStackView {
        let stackView = UIStackView(arrangedSubviews: children)
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }

    // MARK: - Helpers

    static func paragraphStyle(for layout: AnnotationViewLayout) -> NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = layout.lineHeight
        paragraphStyle.maximumLineHeight = layout.lineHeight * 2
        return paragraphStyle
    }

    static func attributedString(from comment: NSAttributedString, layout: AnnotationViewLayout) -> NSAttributedString {
        let string = NSMutableAttributedString(attributedString: comment)
        string.addAttribute(.paragraphStyle, value: AnnotationView.paragraphStyle(for: layout), range: NSRange(location: 0, length: comment.length))
        return string
    }

    static func attributedString(from tags: [Tag], layout: AnnotationViewLayout) -> NSAttributedString {
        let string = AttributedTagStringGenerator.attributedString(from: tags)
        string.addAttribute(.paragraphStyle, value: self.paragraphStyle(for: layout), range: NSRange(location: 0, length: string.length))
        return string
    }
}
