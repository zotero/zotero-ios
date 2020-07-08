//
//  PDFSearchCell.swift
//  Zotero
//
//  Created by Michal Rentka on 08/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import PSPDFKit
import PSPDFKitUI

class PDFSearchCell: UITableViewCell {
    @IBOutlet private weak var pageLabel: UILabel!
    @IBOutlet private weak var contentLabel: UILabel!

    func setup(with searchResult: SearchResult) {
        self.pageLabel.text = L10n.Pdf.AnnotationsSidebar.page + " \(searchResult.pageIndex)"

        let font = UIFont.preferredFont(forTextStyle: .body)
        let highlightAttributes: [NSAttributedString.Key: Any] = [.backgroundColor: UIColor.yellow,
                                                                  .font: font.withTraits(.traitBold)]
        let attributedString = NSMutableAttributedString(string: searchResult.previewText, attributes: [.font: font])
        attributedString.addAttributes(highlightAttributes, range: searchResult.rangeInPreviewText)
        self.contentLabel.attributedText = attributedString
    }
}

#endif
