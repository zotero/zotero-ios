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
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var contentLabel: UILabel!
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
    }

    func setup(with abstract: String, isEditing: Bool) {
        self.contentLabel.text = abstract
        self.contentTextView.text = abstract
        self.contentLabel.isHidden = isEditing
        self.contentTextView.isHidden = !isEditing
    }
}

extension ItemDetailAbstractCell: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        self.observer?.on(.next(textView.text))
    }
}
