//
//  SwitchCell.swift
//  Zotero
//
//  Created by Michal Rentka on 01.12.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class SwitchCell: RxTableViewCell {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var `switch`: UISwitch!

    var switchObservable: Observable<Bool> {
        return self.switch.rx.controlEvent(.valueChanged).flatMap({ Observable.just(self.switch.isOn) })
    }

    func setup(with title: String, isOn: Bool) {
        self.titleLabel.text = title
        self.switch.isOn = isOn
    }
}
