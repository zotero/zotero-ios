//
//  ItemCell.swift
//  Zotero
//
//  Created by Michal Rentka on 17/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemCell: UITableViewCell {
    @IBOutlet private weak var typeImageView: UIImageView!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var subtitleLabel: UILabel!
    @IBOutlet private weak var tagCircles: TagCirclesView!
    @IBOutlet private weak var noteIcon: UIImageView!
    @IBOutlet private weak var fileView: FileAttachmentView!
    
    var key: String = ""

    override func prepareForReuse() {
        super.prepareForReuse()
        self.fileView.tapAction = nil
        self.key = ""
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        self.titleLabel.font = UIFont.preferredFont(for: .headline, weight: .regular)
        self.fileView.contentInsets = UIEdgeInsets(top: 7, left: 8, bottom: 7, right: 15)
        
        let highlightView = UIView()
        highlightView.backgroundColor = Asset.Colors.cellHighlighted.color
        self.selectedBackgroundView = highlightView

        let selectionView = UIView()
        selectionView.backgroundColor = Asset.Colors.cellSelected.color
        self.multipleSelectionBackgroundView = selectionView
    }
    
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        
        if highlighted {
            self.fileView.set(backgroundColor: (self.isEditing ? self.multipleSelectionBackgroundView?.backgroundColor :
                                                                 self.selectedBackgroundView?.backgroundColor))
        } else {
            self.fileView.set(backgroundColor: self.backgroundColor)
        }
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        if selected {
            self.fileView.set(backgroundColor: (self.isEditing ? self.multipleSelectionBackgroundView?.backgroundColor :
                                                                 self.selectedBackgroundView?.backgroundColor))
        } else {
            self.fileView.set(backgroundColor: self.backgroundColor)
        }
    }
    
    private func string(from color: UIColor) -> String {
        var r:CGFloat = 0
        var g:CGFloat = 0
        var b:CGFloat = 0
        var a:CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let rgb:Int = (Int)(r*255)<<16 | (Int)(g*255)<<8 | (Int)(b*255)<<0
        return String(format:"#%06x; %.2f", rgb, a)
    }

    func set(item: ItemCellModel, tapAction: @escaping () -> Void) {
        self.key = item.key
        self.fileView.tapAction = tapAction

        self.typeImageView.image = UIImage(named: item.typeIconName)
        self.titleLabel.text = item.title.isEmpty ? " " : item.title
        self.subtitleLabel.text = item.subtitle.isEmpty ? " " : item.subtitle
        self.subtitleLabel.isHidden = item.subtitle.isEmpty && (item.hasNote || !item.tagColors.isEmpty)
        self.noteIcon.isHidden = !item.hasNote

        self.tagCircles.isHidden = item.tagColors.isEmpty
        if !self.tagCircles.isHidden {
            self.tagCircles.colors = item.tagColors
        }

        if let (contentType, progress, error) = item.attachment {
            self.fileView.set(contentType: contentType, progress: progress, error: error, style: .list)
            self.fileView.isHidden = false
        } else {
            self.fileView.isHidden = true
        }
    }

    func set(contentType: Attachment.ContentType, progress: CGFloat?, error: Error?) {
        self.fileView.set(contentType: contentType, progress: progress, error: error, style: .list)
        self.fileView.isHidden = false
    }

    func clearAttachment() {
        self.fileView.isHidden = true
    }
}
