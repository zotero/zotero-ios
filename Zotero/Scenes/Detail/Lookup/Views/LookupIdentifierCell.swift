//
//  LookupIdentifierCell.swift
//  Zotero
//
//  Created by Michal Rentka on 22.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class LookupIdentifierCell: UITableViewCell {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var detailLabel: UILabel!
    @IBOutlet private weak var activityIndicator: UIActivityIndicatorView!

    override func awakeFromNib() {
        super.awakeFromNib()
        self.backgroundColor = .clear
        self.contentView.backgroundColor = .clear
    }

    func set(title: String, state: LookupViewController.Row.IdentifierState, hasDarkBackground: Bool) {
        self.titleLabel.text = title
        self.titleLabel.textColor = hasDarkBackground ? .white : .label
        if hasDarkBackground {
            self.activityIndicator.color = .white
        }

        switch state {
        case .inProgress:
            self.detailLabel.text = ""
            self.detailLabel.isHidden = true
            self.activityIndicator.isHidden = false
            self.activityIndicator.startAnimating()

        case .failed:
            self.detailLabel.isHidden = false
            self.detailLabel.text = "Failed"
            self.detailLabel.textColor = .red
            self.activityIndicator.stopAnimating()
            self.activityIndicator.isHidden = true

        case .enqueued:
            self.detailLabel.isHidden = false
            self.detailLabel.text = "Queued..."
            self.detailLabel.textColor = .systemGray
            self.activityIndicator.stopAnimating()
            self.activityIndicator.isHidden = true
        }
    }
}
