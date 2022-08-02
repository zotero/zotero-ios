//
//  UICollectionViewListCell+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 02.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class RxCollectionViewListCell: UICollectionViewListCell {
    var disposeBag: DisposeBag = DisposeBag()
    var newDisposeBag: DisposeBag {
        self.disposeBag = DisposeBag()
        return self.disposeBag
    }
}

extension UIView {
    func add(contentView view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(view)

        NSLayoutConstraint.activate([
            NSLayoutConstraint(item: view, attribute: .leading, relatedBy: .equal, toItem: self, attribute: .leadingMargin, multiplier: 1.0, constant: 0),
            NSLayoutConstraint(item: self, attribute: .trailingMargin, relatedBy: .equal, toItem: view, attribute: .trailing, multiplier: 1.0, constant: 0),
            NSLayoutConstraint(item: self, attribute: .topMargin, relatedBy: .equal, toItem: view, attribute: .top, multiplier: 1.0, constant: 0),
            NSLayoutConstraint(item: self, attribute: .bottomMargin, relatedBy: .equal, toItem: view, attribute: .bottom, multiplier: 1.0, constant: 0)
        ])
    }
}
