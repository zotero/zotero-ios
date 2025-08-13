//
//  DocumentSearchCell.swift
//  Zotero
//
//  Created by Michal Rentka on 08/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class DocumentSearchCell: UITableViewCell {
    @IBOutlet private weak var pageLabel: UILabel!
    @IBOutlet private weak var contentLabel: UILabel!

    func setup(with result: DocumentSearchResult) {
        if let label = result.pageLabel {
            self.pageLabel.text = L10n.page + " " + label
        } else {
            self.pageLabel.text = nil
        }
        let font = UIFont.preferredFont(forTextStyle: .body)
        let highlightAttributes: [NSAttributedString.Key: Any] = [.backgroundColor: UIColor.yellow, .font: font.with(traits: .traitBold, attributes: [:])]
        let attributedString = NSMutableAttributedString(string: result.snippet, attributes: [.font: font])
        attributedString.addAttributes(highlightAttributes, range: result.highlightRange)
        self.contentLabel.attributedText = attributedString
    }
}
