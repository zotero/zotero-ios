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
    var disposeBag: DisposeBag = DisposeBag()
    var newDisposeBag: DisposeBag {
        self.disposeBag = DisposeBag()
        return self.disposeBag
    }
}
