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
        actionPublisher = PublishSubject()

        super.init(frame: CGRect())

        backgroundColor = layout.backgroundColor
        translatesAutoresizingMaskIntoConstraints = false
        setupView(commentPlaceholder: commentPlaceholder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions

    @discardableResult
    override func resignFirstResponder() -> Bool {
        commentTextView.resignFirstResponder()
    }

    func updatePreview(image: UIImage?) {
        guard let imageContent, !imageContent.isHidden else { return }
        imageContent.setup(with: image)
    }

    private func scrollToBottomIfNeeded() {
        guard let scrollView, let scrollViewContent, scrollViewContent.frame.height > scrollView.frame.height else { return }
        let yOffset = scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom
        scrollView.setContentOffset(CGPoint(x: 0, y: yOffset), animated: true)
    }

    // MARK: - Setups

    /// Setups up annotation view with given annotation and additional data.
    /// - parameter annotation: Annotation to show in view.
    /// - parameter text: Text to show. If nil, text field is not shown.
    /// - parameter comment: Comment to show. If nil, comment field is not shown.
    /// - parameter preview: Preview image to show. If nil, no image is shown.
    /// - parameter selected: If true, selected state style is applied.
    /// - parameter availableWidth: Available width for view.
    /// - parameter library: Library of given annotation
    /// - parameter pdfAnnotationsCoordinatorDelegate: Delegate for getting share menu.
    /// - parameter state: State required for setting up share menu.
    func setup(
        with annotation: PDFAnnotation,
        text: NSAttributedString?,
        comment: Comment?,
        preview: UIImage?,
        selected: Bool,
        availableWidth: CGFloat,
        library: Library,
        currentUserId: Int,
        displayName: String,
        username: String,
        boundingBoxConverter: AnnotationBoundingBoxConverter,
        pdfAnnotationsCoordinatorDelegate: PdfAnnotationsCoordinatorDelegate,
        state: PDFReaderState
    ) {
        let editability = annotation.editability(currentUserId: currentUserId, library: library)
        let color = UIColor(hex: annotation.color)
        let canEdit = editability == .editable && selected
        let author = library.identifier == .custom(.myLibrary) ? "" : annotation.author(displayName: displayName, username: username)

        header.setup(
            type: annotation.type,
            authorName: author,
            pageLabel: annotation.pageLabel,
            colorHex: annotation.color,
            shareMenuProvider: { button in
                pdfAnnotationsCoordinatorDelegate.createShareAnnotationMenu(state: state, annotation: annotation, sender: button)
            },
            isEditable: (editability != .notEditable && selected),
            showsLock: editability != .editable,
            accessibilityType: .cell
        )
        setupContent(
            for: annotation,
            text: text,
            preview: preview,
            color: color,
            canEdit: canEdit,
            selected: selected,
            availableWidth: availableWidth,
            accessibilityType: .cell,
            boundingBoxConverter: boundingBoxConverter
        )
        setup(comment: comment, canEdit: canEdit)
        setup(tags: annotation.tags, canEdit: canEdit, accessibilityEnabled: selected)

        let commentButtonIsHidden = commentTextView.isHidden
        let highlightContentIsHidden = highlightContent?.isHidden ?? true
        let imageContentIsHidden = imageContent?.isHidden ?? true

        // Top separator is hidden only if there is only header visible and nothing else
        topSeparator.isHidden = commentTextView.isHidden && commentButtonIsHidden && highlightContentIsHidden && imageContentIsHidden && tags.isHidden && tagsButton.isHidden
        // Bottom separator is visible, when tags are showing (either actual tags or tags button) and there is something visible above them (other than header, either content or comments/comments button)
        bottomSeparator.isHidden = (tags.isHidden && tagsButton.isHidden) || (commentTextView.isHidden && commentButtonIsHidden && highlightContentIsHidden && imageContentIsHidden)
    }

    private func setupContent(
        for annotation: PDFAnnotation,
        text: NSAttributedString?,
        preview: UIImage?,
        color: UIColor,
        canEdit: Bool,
        selected: Bool,
        availableWidth: CGFloat,
        accessibilityType: AccessibilityType,
        boundingBoxConverter: AnnotationBoundingBoxConverter
    ) {
        guard let highlightContent, let imageContent else { return }

        highlightContent.isUserInteractionEnabled = false

        switch annotation.type {
        case .note:
            highlightContent.isHidden = true
            imageContent.isHidden = true

        case .highlight, .underline:
            let bottomInset = inset(from: layout.highlightLineVerticalInsets, hasComment: !annotation.comment.isEmpty, selected: selected, canEdit: canEdit)
            highlightContent.isHidden = false
            imageContent.isHidden = true
            highlightContent.setup(with: color, text: text ?? .init(), bottomInset: bottomInset, accessibilityType: accessibilityType)

        case .image, .ink, .freeText:
            highlightContent.isHidden = true
            imageContent.isHidden = false
            let size = annotation.previewBoundingBox(boundingBoxConverter: boundingBoxConverter).size
            let maxWidth = availableWidth - (layout.horizontalInset * 2)
            var maxHeight = ceil((size.height / size.width) * maxWidth)
            if maxHeight.isNaN || maxHeight.isInfinite {
                maxHeight = maxWidth * 2
            } else {
                maxHeight = min((maxWidth * 2), maxHeight)
            }
            let bottomInset = inset(from: layout.verticalSpacerHeight, hasComment: !annotation.comment.isEmpty, selected: selected, canEdit: canEdit)
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
            commentTextView.isHidden = true
            return
        }

        commentTextView.isHidden = false
        commentTextView.isUserInteractionEnabled = canEdit

        // If comment is empty and not active, the input acts as a button.
        if isEmptyComment && !comment.isActive {
            commentTextView.set(placeholderColor: Asset.Colors.zoteroBlue.color)
            commentTextView.setup(text: nil)
            return
        }

        // If there is any comment or the comment is active, the input acts as a text view with a placeholder.
        let attributedString = comment.attributedString.flatMap({ AnnotationView.attributedString(from: $0, layout: layout) })
        commentTextView.set(placeholderColor: .placeholderText)
        commentTextView.setup(text: attributedString)

        if canEdit && comment.isActive {
            commentTextView.becomeFirstResponder()
        }
    }

    private func setup(tags: [Tag], canEdit: Bool, accessibilityEnabled: Bool) {
        guard !tags.isEmpty else {
            tagsButton.isHidden = !canEdit
            tagsButton.accessibilityLabel = L10n.Pdf.AnnotationsSidebar.addTags
            tagsButton.isAccessibilityElement = true
            self.tags.isHidden = true
            return
        }

        let tagString = AnnotationView.attributedString(from: tags, layout: layout)
        self.tags.setup(with: tagString)

        tagsButton.isHidden = true
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
        commentTextView.didBecomeActive.subscribe(onNext: { [weak self] _ in
            self?.actionPublisher.on(.next(.setCommentActive(true)))
        })
        commentTextView.textObservable
            .debounce(.milliseconds(500), scheduler: MainScheduler.instance)
            .subscribe(onNext: { [weak self] data in
                guard let self = self, let (text, needsHeightReload) = data else { return }
                actionPublisher.on(.next(.setComment(text)))
                if needsHeightReload {
                    actionPublisher.on(.next(.reloadHeight))
                    scrollToBottomIfNeeded()
                }
            })
        tags.tap.flatMap({ _ in Observable.just(Action.tags) }).bind(to: actionPublisher)
        tagsButton.rx.tap.flatMap({ Observable.just(Action.tags) }).bind(to: actionPublisher)
        header.menuTap.flatMap({ Observable.just(Action.options($0)) }).bind(to: actionPublisher)
    }
    
    func setupObserving() {
        var disposables: [Disposable] = buildDisposables()
        if let doneTap = header.doneTap {
            disposables.append(doneTap.flatMap({ Observable.just(Action.done) }).bind(to: actionPublisher))
        }
        disposeBag = CompositeDisposable(disposables: disposables)
    }

    private func setupView(commentPlaceholder: String) {
        header = AnnotationViewHeader(layout: layout)
        topSeparator = AnnotationViewSeparator()
        commentTextView = AnnotationViewTextView(layout: layout, placeholder: commentPlaceholder)
        commentTextView.accessibilityLabelPrefix = L10n.Accessibility.Pdf.comment + ": "
        bottomSeparator = AnnotationViewSeparator()
        tagsButton = AnnotationViewButton(layout: layout)
        tagsButton.setTitle(L10n.Pdf.AnnotationsSidebar.addTags, for: .normal)
        tags = AnnotationViewText(layout: layout)

        if layout.showsContent {
            highlightContent = AnnotationViewHighlightContent(layout: layout)
            imageContent = AnnotationViewImageContent(layout: layout)
        }

        let view = layout.scrollableBody ? createScrollableBodyView() : createStaticBodyView()
        addSubview(view)

        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    private func createStaticBodyView() -> UIView {
        var views: [UIView] = [header, topSeparator]
        if layout.showsContent {
            if let highlightContent {
                views.append(highlightContent)
            }
            if let imageContent {
                views.append(imageContent)
            }
        }
        views.append(contentsOf: [commentTextView, bottomSeparator, tagsButton, tags])
        return createStackView(with: views)
    }

    private func createScrollableBodyView() -> UIView {
        let stackView = createStackView(with: [commentTextView, bottomSeparator, tagsButton, tags])
        scrollViewContent = stackView

        let scrollView = UIScrollView()
        scrollView.addSubview(stackView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView = scrollView

        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        view.addSubview(topSeparator)
        view.addSubview(scrollView)

        let height = stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        height.priority = .defaultHigh

        NSLayoutConstraint.activate([
            // Vertical
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.bottomAnchor.constraint(equalTo: topSeparator.topAnchor),
            topSeparator.bottomAnchor.constraint(equalTo: scrollView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            height,
            // Horizontal
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
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
        string.addAttribute(.paragraphStyle, value: paragraphStyle(for: layout), range: NSRange(location: 0, length: string.length))
        return string
    }
}
