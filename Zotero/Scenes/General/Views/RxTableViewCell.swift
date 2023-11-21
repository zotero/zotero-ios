//
//  RxTableViewCell.swift
//  Zotero
//
//  Created by Michal Rentka on 20/05/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class RxTableViewCell: UITableViewCell {
    private(set) var disposeBag: DisposeBag = DisposeBag()

    override func prepareForReuse() {
        super.prepareForReuse()
        disposeBag = DisposeBag()
    }
}
