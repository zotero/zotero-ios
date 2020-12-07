//
//  AnnotationView.swift
//  Zotero
//
//  Created by Michal Rentka on 13/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class AnnotationView: UIView {
    enum Kind {
        case cell, popover
    }

    enum Action {
        case tags
        case options(UIButton)
        case reloadHeight
        case setComment(NSAttributedString)
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

    private var shouldHalveTopInset: Bool {
        let highlightContentIsHidden = self.highlightContent?.isHidden ?? true
        let imageContentIsHidden = self.imageContent?.isHidden ?? true
        return !highlightContentIsHidden || !imageContentIsHidden
    }

    // MARK: - Lifecycle

    init(layout: AnnotationViewLayout) {
        self.layout = layout
        self.actionPublisher = PublishSubject()

        super.init(frame: CGRect())

        self.backgroundColor = UIColor(dynamicProvider: { traitCollection -> UIColor in
            return traitCollection.userInterfaceStyle == .dark ? .black : .white
        })
        self.translatesAutoresizingMaskIntoConstraints = false
        self.setupView()
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

    private func addComment() {
        self.commentButton?.isHidden = true
        self.commentTextView.setup(text: nil, halfTopInset: self.shouldHalveTopInset)
        self.commentTextView.isHidden = false
        self.layoutIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.commentTextView.becomeFirstResponder()
        }
    }

    private func scrollToBottomIfNeeded() {
        guard let scrollView = self.scrollView, let contentView = self.scrollViewContent, contentView.frame.height > scrollView.frame.height else { return }
        let yOffset = scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom
        scrollView.setContentOffset(CGPoint(x: 0, y: yOffset), animated: true)
    }

    // MARK: - Setups

    func setupHeader(with annotation: Annotation, selected: Bool, hasWritePermission: Bool) {
        let color = UIColor(hex: annotation.color)
        self.header.setup(type: annotation.type, color: color, pageLabel: annotation.pageLabel, author: annotation.author, showsMenuButton: (hasWritePermission && selected))
    }

    func setup(with annotation: Annotation, attributedComment: NSAttributedString?, preview: UIImage?, selected: Bool, availableWidth: CGFloat, hasWritePermission: Bool) {
        let color = UIColor(hex: annotation.color)
        let canEdit = selected && (hasWritePermission || annotation.isAuthor)

        self.header.setup(type: annotation.type, color: color, pageLabel: annotation.pageLabel,
                          author: annotation.author, showsMenuButton: (hasWritePermission && selected))
        self.setupContent(for: annotation, preview: preview, color: color, canEdit: canEdit, availableWidth: availableWidth)
        self.setupComments(for: annotation, attributedComment: attributedComment, canEdit: canEdit)
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

    private func setupContent(for annotation: Annotation, preview: UIImage?, color: UIColor, canEdit: Bool, availableWidth: CGFloat) {
        guard let highlightContent = self.highlightContent, let imageContent = self.imageContent else { return }

        highlightContent.isUserInteractionEnabled = false
        highlightContent.isHidden = annotation.type != .highlight
        imageContent.isHidden = annotation.type != .image

        switch annotation.type {
        case .note: break

        case .highlight:
            highlightContent.setup(with: color, text: (annotation.text ?? ""), halfBottomInset: !annotation.comment.isEmpty)

        case .image:
            let size = annotation.boundingBox.size
            let maxWidth = availableWidth - (self.layout.horizontalInset * 2)
            let maxHeight = (size.height / size.width) * maxWidth
            imageContent.setup(with: preview, height: maxHeight, halfBottomInset: annotation.comment.isEmpty)
        }
    }

    private func setupComments(for annotation: Annotation, attributedComment: NSAttributedString?, canEdit: Bool) {
        guard self.layout.alwaysShowComment || !annotation.comment.isEmpty else {
            self.commentButton?.isHidden = !canEdit
            self.commentTextView.isHidden = true
            return
        }

        let comment = attributedComment.flatMap({ self.attributedString(from: $0) })

        self.commentTextView.setup(text: comment, halfTopInset: self.shouldHalveTopInset)

        self.commentButton?.isHidden = true
        self.commentTextView.isHidden = false
        self.commentTextView.isUserInteractionEnabled = canEdit
    }

    private func setupTags(for annotation: Annotation, canEdit: Bool) {
        guard !annotation.tags.isEmpty else {
            self.tagsButton.isHidden = !canEdit
            self.tags.isHidden = true
            return
        }

        self.tags.setup(with: self.attributedString(from: annotation.tags), halfTopInset: false)

        self.tagsButton.isHidden = true
        self.tags.isHidden = false
        self.tags.isUserInteractionEnabled = canEdit
    }

    private func setupObserving() {
        self.disposeBag = DisposeBag()

        self.commentButton?.rx.tap.subscribe(onNext: { [weak self] _ in self?.addComment() }).disposed(by: self.disposeBag)

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
    }

    private func setupView() {
        self.header = AnnotationViewHeader(layout: self.layout)
        self.topSeparator = AnnotationViewSeparator()
        self.commentTextView = AnnotationViewTextView(layout: self.layout, placeholder: L10n.Pdf.AnnotationsSidebar.addComment)
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
        return self.createStackView(with: [self.header, self.topSeparator, self.highlightContent!, self.imageContent!, self.commentButton!,
                                           self.commentTextView, self.bottomSeparator, self.tagsButton, self.tags])
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

    private var paragraphStyle: NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = self.layout.lineHeight
        paragraphStyle.maximumLineHeight = self.layout.lineHeight
        return paragraphStyle
    }

    private func attributedString(from comment: NSAttributedString) -> NSAttributedString {
        let string = NSMutableAttributedString(attributedString: comment)
        string.addAttribute(.paragraphStyle, value: self.paragraphStyle, range: NSRange(location: 0, length: comment.length))
        return string
    }

    private func attributedString(from tags: [Tag]) -> NSAttributedString {
        let wholeString = NSMutableAttributedString()
        for (index, tag) in tags.enumerated() {
            let string = NSAttributedString(string: tag.name, attributes: [.foregroundColor: TagColorGenerator.uiColor(for: tag.color).color])
            wholeString.append(string)
            if index != (tags.count - 1) {
                wholeString.append(NSAttributedString(string: ", "))
            }
        }
        wholeString.addAttribute(.paragraphStyle, value: self.paragraphStyle, range: NSRange(location: 0, length: wholeString.length))
        return wholeString
    }
}
