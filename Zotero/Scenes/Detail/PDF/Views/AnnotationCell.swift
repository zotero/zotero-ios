//
//  AnnotationCell.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

typealias AnnotationCellAction = (AnnotationCell.Action, UIButton) -> Void

class AnnotationCell: UITableViewCell {
    enum Action {
        case comment, tags, options
    }

    @IBOutlet private weak var roundedContainer: UIView!
    // Header
    @IBOutlet private weak var annotationIcon: UIImageView!
    @IBOutlet private weak var pageLabel: UILabel!
    @IBOutlet private weak var authorLabel: UILabel!
    @IBOutlet private weak var firstSeparator: UIView!
    @IBOutlet private weak var headerButton: UIButton!
    // Content
    @IBOutlet private weak var annotationContainer: UIView!
    @IBOutlet private weak var annotationTextContainer: UIStackView!
    @IBOutlet private weak var annotationTextHighlightView: UIView!
    @IBOutlet private weak var annotationTextLabel: UILabel!
    @IBOutlet private weak var annotationImageView: UIImageView!
    @IBOutlet private weak var commentContainer: UIView!
    @IBOutlet private weak var commentLabel: UILabel!
    @IBOutlet private weak var commentButton: UIButton!
    @IBOutlet private weak var addCommentContainer: UIView!
    @IBOutlet private weak var addCommentButton: UIButton!
    @IBOutlet private weak var secondSeparator: UIView!
    private var annotationImageHeight: NSLayoutConstraint!
    // Footer
    @IBOutlet private weak var tagsContainer: UIView!
    @IBOutlet private weak var tagsLabel: UILabel!
    @IBOutlet private weak var tagsButton: UIButton!
    @IBOutlet private weak var addTagsContainer: UIView!
    @IBOutlet private weak var addTagsButton: UIButton!

    private static let annotationImageHorizontalInsets: CGFloat = 32

    private(set) var key: String = ""

    var performAction: AnnotationCellAction?

    override func awakeFromNib() {
        super.awakeFromNib()

        self.selectionStyle = .none

        self.roundedContainer.layer.cornerRadius = 8
        self.roundedContainer.layer.borderWidth = 1
        self.roundedContainer.layer.shadowOpacity = 1
        self.roundedContainer.layer.shadowRadius = 2
        self.roundedContainer.layer.shadowOffset = CGSize()

        self.annotationImageHeight = self.annotationImageView.heightAnchor.constraint(equalToConstant: 0)

        self.addCommentButton.setTitle(L10n.Pdf.AnnotationsSidebar.addComment, for: .normal)
        self.addTagsButton.setTitle(L10n.Pdf.AnnotationsSidebar.addTags, for: .normal)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.key = ""
    }

    @IBAction private func updateComment(sender: UIButton) {
        self.performAction?(.comment, sender)
    }

    @IBAction private func updateTags(sender: UIButton) {
        self.performAction?(.tags, sender)
    }

    @IBAction private func showOptions(sender: UIButton) {
        self.performAction?(.options, sender)
    }

    func updatePreview(image: UIImage?) {
        guard !self.annotationImageView.isHidden else { return }
        self.annotationImageView.image = image
    }

    func setup(with annotation: Annotation, preview: UIImage?, selected: Bool, availableWidth: CGFloat) {
        self.key = annotation.key

        // Setup visuals
        self.roundedContainer.backgroundColor = self.contentBackgroundColor(selected: selected)
        self.roundedContainer.layer.shadowColor = self.shadowColor(selected: selected).cgColor
        self.roundedContainer.layer.borderColor = self.borderColor(selected: selected).cgColor

        // Setup visibility of individual containers
        self.annotationContainer.isHidden = annotation.type != .highlight && annotation.type != .area
        self.annotationTextContainer.isHidden = annotation.type != .highlight
        self.annotationImageView.isHidden = !self.annotationTextContainer.isHidden
        self.annotationImageHeight.isActive = !self.annotationImageView.isHidden
        self.commentContainer.isHidden = annotation.comment.isEmpty
        self.addCommentContainer.isHidden = !self.commentContainer.isHidden || !selected
        self.firstSeparator.isHidden = self.annotationContainer.isHidden && self.commentContainer.isHidden && self.addCommentContainer.isHidden
        self.tagsContainer.isHidden = annotation.tags.isEmpty
        self.addTagsContainer.isHidden = !self.tagsContainer.isHidden || !selected
        self.secondSeparator.isHidden = self.tagsContainer.isHidden && self.addTagsContainer.isHidden

        let color = UIColor(hex: annotation.color)

        // Header
        self.annotationIcon.image = self.image(for: annotation.type)?.withRenderingMode(.alwaysTemplate)
        self.annotationIcon.tintColor = color
        self.pageLabel.text = "\(L10n.Pdf.AnnotationsSidebar.page) \(annotation.pageLabel)"
        self.authorLabel.text = annotation.author
        self.headerButton.isEnabled = !annotation.isLocked
        self.headerButton.tintColor = annotation.isLocked ? .black : .systemBlue
        self.headerButton.setImage(UIImage(systemName: annotation.isLocked ? "lock" : "ellipsis.circle"), for: .normal)
        self.headerButton.isHidden = !annotation.isLocked && !selected
        self.headerButton.contentEdgeInsets = UIEdgeInsets(top: 0,
                                                           left: self.headerButton.isHidden ? 0 : 10,
                                                           bottom: 0,
                                                           right: 10)
        // Annotation
        switch annotation.type {
        case .highlight:
            self.annotationTextHighlightView.backgroundColor = color
            self.annotationTextLabel.text = annotation.text
        case .area:
            self.annotationImageView.image = preview
            let size = annotation.boundingBox.size
            let maxWidth = availableWidth - AnnotationCell.annotationImageHorizontalInsets
            let maxHeight = (size.height / size.width) * maxWidth
            self.annotationImageHeight.constant = maxHeight
        case .note: break
        }
        // Comment
        self.commentLabel.text = annotation.comment
        // Tags
        self.tagsLabel.attributedText = self.attributedString(from: annotation.tags)

        self.commentButton.isEnabled = selected
        self.addCommentButton.isEnabled = selected
        self.tagsButton.isEnabled = selected
        self.addTagsButton.isEnabled = selected
    }

    private func image(for type: Annotation.Kind) -> UIImage? {
        switch type {
        case .area: return UIImage(named: "annotation_area")
        case .highlight: return UIImage(named: "annotation_highlight")
        case .note: return UIImage(named: "annotation_note")
        }
    }

    private func attributedString(from tags: [Tag]) -> NSAttributedString {
        let wholeString = NSMutableAttributedString()
        for (index, tag) in tags.enumerated() {
            let string = NSAttributedString(string: tag.name, attributes: [.foregroundColor: UIColor(hex: tag.color)])
            wholeString.append(string)
            if index != (tags.count - 1) {
                wholeString.append(NSAttributedString(string: ", "))
            }
        }
        return wholeString
    }

    // MARK: - Colors

    private func shadowColor(selected: Bool) -> UIColor {
        return selected ? UIColor(hex: "#6d95e0") : .clear
    }

    private func borderColor(selected: Bool) -> UIColor {
        return UIColor(hex: selected ? "#6d95e0" : "#bcc4d2")
    }

    private func contentBackgroundColor(selected: Bool) -> UIColor {
        return selected ? UIColor(hex: "#e4ebf9") : .white
    }
}
