//
//  ItemDetailAbstractCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxCocoa
import RxSwift

class ItemDetailAbstractCell: RxTableViewCell {
    enum State {
        case editing
        case collapsed
        case expanded
    }

    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var contentLabel: CollapsibleLabel!
    @IBOutlet private weak var contentTextView: UITextView!

    private var observer: AnyObserver<String>?
    var textObservable: Observable<String> {
        return Observable.create { observer -> Disposable in
            self.observer = observer
            return Disposables.create()
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        self.titleLabel.font = UIFont.preferredFont(for: .headline, weight: .regular)
        self.contentTextView.delegate = self

        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13),
                                                         .foregroundColor: Asset.Colors.zoteroBlue.color]
        let showMore = NSMutableAttributedString(string: " ... ")
        showMore.append(NSAttributedString(string: L10n.ItemDetail.showMore, attributes: attributes))

        self.contentLabel.collapsedNumberOfLines = 2
        self.contentLabel.showLessString = NSAttributedString(string: L10n.ItemDetail.showLess, attributes: attributes)
        self.contentLabel.showMoreString = showMore
    }

    func setup(with abstract: String, state: State) {
        switch state {
        case .editing:
            self.contentTextView.text = abstract

        case .collapsed, .expanded:
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.hyphenationFactor = 1
            paragraphStyle.alignment = .justified
            let attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: paragraphStyle,
                                                             .font: UIFont.preferredFont(forTextStyle: .body)]
            let hyphenatedText = NSAttributedString(string: abstract, attributes: attributes)

            self.contentLabel.set(text: hyphenatedText, isCollapsed: (state == .collapsed))
        }

        self.contentLabel.isHidden = state == .editing
        self.contentTextView.isHidden = !self.contentLabel.isHidden
    }
}

extension ItemDetailAbstractCell: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        self.observer?.on(.next(textView.text))
    }
}
