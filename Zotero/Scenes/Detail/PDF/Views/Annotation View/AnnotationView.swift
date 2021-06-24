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
        case options(UIButton)
        case reloadHeight
        case setComment(NSAttributedString)
        case setCommentActive(Bool)
        case done
    }

    private let layout: AnnotationViewLayout
    let actionPublisher: PublishSubject<AnnotationView.Action>

    private var header: AnnotationViewHeader!
    private var topSeparator: UIView!
    private var highlightContent: AnnotationViewHighlightContent?
    private var imageContent: AnnotationViewImageContent?
    private var commentButton: AnnotationViewButton?
    private var commentTextView: AnnotationViewTextView!
    private var bottomSeparator: UIView!
    private var tagsButton: AnnotationViewButton!
    private var tags: AnnotationViewText!
    private var scrollView: UIScrollView?
    private var scrollViewContent: UIView?
    private(set) var disposeBag: DisposeBag!

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

    func setupHeader(with annotation: Annotation, selected: Bool, hasWritePermission: Bool) {
        self.header.setup(with: annotation, isEditable: (hasWritePermission && selected), showDoneButton: self.layout.showDoneButton)
    }

    func setup(with annotation: Annotation, attributedComment: NSAttributedString?, preview: UIImage?, selected: Bool, commentActive: Bool, availableWidth: CGFloat, hasWritePermission: Bool) {
        let color = UIColor(hex: annotation.color)
        let canEdit = (annotation.editability != .notEditable) && selected && (hasWritePermission || annotation.isAuthor)

        self.header.setup(with: annotation, isEditable: canEdit, showDoneButton: self.layout.showDoneButton)
        self.setupContent(for: annotation, preview: preview, color: color, canEdit: canEdit, selected: selected, availableWidth: availableWidth)
        self.setupComments(for: annotation, attributedComment: attributedComment, isActive: commentActive, canEdit: canEdit)
        self.setupTags(for: annotation, canEdit: canEdit)
        self.setupObserving()

        let commentButtonIsHidden = self.commentButton?.isHidden ?? true
        let highlightContentIsHidden = self.highlightContent?.isHidden ?? true
        let imageContentIsHidden = self.imageContent?.isHidden ?? true

        // Top separator is hidden only if there is only header visible and nothing else
        self.topSeparator.isHidden = self.commentTextView.isHidden && commentButtonIsHidden && highlightContentIsHidden && imageContentIsHidden && self.tags.isHidden && self.tagsButton.isHidden
        // Bottom separator is visible, when tags are showing (either actual tags or tags button) and there is something visible above them (other than header, either content or comments/comments button)
        self.bottomSeparator.isHidden = (self.tags.isHidden && self.tagsButton.isHidden) || (self.commentTextView.isHidden && commentButtonIsHidden && highlightContentIsHidden && imageContentIsHidden)
    }

    private func setupContent(for annotation: Annotation, preview: UIImage?, color: UIColor, canEdit: Bool, selected: Bool, availableWidth: CGFloat) {
        guard let highlightContent = self.highlightContent, let imageContent = self.imageContent else { return }

        highlightContent.isUserInteractionEnabled = false
        highlightContent.isHidden = annotation.type != .highlight
        imageContent.isHidden = annotation.type != .image

        switch annotation.type {
        case .note: break

        case .highlight:
            let bottomInset = self.inset(from: self.layout.highlightLineVerticalInsets, hasComment: !annotation.comment.isEmpty, selected: selected, canEdit: canEdit)
            highlightContent.setup(with: color, text: (annotation.text ?? ""), bottomInset: bottomInset)

        case .image:
            let size = annotation.previewBoundingBox.size
            let maxWidth = availableWidth - (self.layout.horizontalInset * 2)
            let maxHeight = ceil((size.height / size.width) * maxWidth)
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

    private func setupComments(for annotation: Annotation, attributedComment: NSAttributedString?, isActive: Bool, canEdit: Bool) {
        guard isActive || !annotation.comment.isEmpty else {
            self.commentButton?.isHidden = !canEdit
            self.commentTextView.isHidden = true
            return
        }

        let comment = attributedComment.flatMap({ AnnotationView.attributedString(from: $0, layout: self.layout) })
        self.commentTextView.setup(text: comment)

        self.commentButton?.isHidden = true
        self.commentTextView.isHidden = false
        self.commentTextView.isUserInteractionEnabled = canEdit
        if canEdit && isActive {
            self.commentTextView.becomeFirstResponder()
        }
    }

    private func setupTags(for annotation: Annotation, canEdit: Bool) {
        guard !annotation.tags.isEmpty else {
            self.tagsButton.isHidden = !canEdit
            self.tags.isHidden = true
            return
        }

        self.tags.setup(with: AnnotationView.attributedString(from: annotation.tags, layout: self.layout))

        self.tagsButton.isHidden = true
        self.tags.isHidden = false
        self.tags.isUserInteractionEnabled = canEdit
    }

    private func setupObserving() {
        self.disposeBag = DisposeBag()

        self.commentButton?.rx.tap.subscribe(onNext: { [weak self] _ in
            self?.actionPublisher.on(.next(.setCommentActive(true)))
        })
        .disposed(by: self.disposeBag)

        self.commentTextView.textObservable.subscribe(onNext: { [weak self] text, needsHeightReload in
            self?.actionPublisher.on(.next(.setComment(text)))
            if needsHeightReload {
                self?.actionPublisher.on(.next(.reloadHeight))
                self?.scrollToBottomIfNeeded()
            }
        })
        .disposed(by: self.disposeBag)

        self.tags.tap.flatMap({ _ in Observable.just(Action.tags) }).bind(to: self.actionPublisher).disposed(by: self.disposeBag)
        self.tagsButton.rx.tap.flatMap({ Observable.just(Action.tags) }).bind(to: self.actionPublisher).disposed(by: self.disposeBag)
        self.header.menuTap.flatMap({ Observable.just(Action.options($0)) }).bind(to: self.actionPublisher).disposed(by: self.disposeBag)
        if let doneTap = self.header.doneTap {
            doneTap.flatMap({ Observable.just(Action.done) }).bind(to: self.actionPublisher).disposed(by: self.disposeBag)
        }
    }

    private func setupView(commentPlaceholder: String) {
        self.header = AnnotationViewHeader(layout: self.layout)
        self.topSeparator = AnnotationViewSeparator()
        self.commentTextView = AnnotationViewTextView(layout: self.layout, placeholder: commentPlaceholder)
        self.bottomSeparator = AnnotationViewSeparator()
        self.tagsButton = AnnotationViewButton(layout: self.layout)
        self.tagsButton.setTitle(L10n.Pdf.AnnotationsSidebar.addTags, for: .normal)
        self.tags = AnnotationViewText(layout: self.layout)

        if self.layout.showsContent {
            self.highlightContent = AnnotationViewHighlightContent(layout: self.layout)
            self.imageContent = AnnotationViewImageContent(layout: self.layout)
            self.commentButton = AnnotationViewButton(layout: self.layout)
            self.commentButton?.setTitle(L10n.Pdf.AnnotationsSidebar.addComment, for: .normal)
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
            if let commentButton = self.commentButton {
                views.append(commentButton)
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
        paragraphStyle.maximumLineHeight = layout.lineHeight
        return paragraphStyle
    }

    static func attributedString(from comment: NSAttributedString, layout: AnnotationViewLayout) -> NSAttributedString {
        let string = NSMutableAttributedString(attributedString: comment)
        string.addAttribute(.paragraphStyle, value: AnnotationView.paragraphStyle(for: layout), range: NSRange(location: 0, length: comment.length))
        return string
    }

    static func attributedString(from tags: [Tag], layout: AnnotationViewLayout) -> NSAttributedString {
        let wholeString = NSMutableAttributedString()
        for (index, tag) in tags.enumerated() {
            let tagInfo = TagColorGenerator.uiColor(for: tag.color)
            let color: UIColor
            switch tagInfo.style {
            case .border:
                // Overwrite default gray color
                color = UIColor(dynamicProvider: { traitCollection -> UIColor in
                    return traitCollection.userInterfaceStyle == .dark ? .white : .darkText
                })
            case .filled:
                color = tagInfo.color
            }
            let string = NSAttributedString(string: tag.name, attributes: [.foregroundColor: color])
            wholeString.append(string)
            if index != (tags.count - 1) {
                wholeString.append(NSAttributedString(string: ", "))
            }
        }
        wholeString.addAttribute(.paragraphStyle, value: self.paragraphStyle(for: layout), range: NSRange(location: 0, length: wholeString.length))
        return wholeString
    }
}
