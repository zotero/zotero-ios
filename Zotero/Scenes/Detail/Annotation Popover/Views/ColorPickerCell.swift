//
//  ColorPickerCell.swift
//  Zotero
//
//  Created by Michal Rentka on 27.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class ColorPickerCell: UITableViewCell {
    @IBOutlet private weak var stackView: UIStackView!

    let colorChange: PublishSubject<String> = PublishSubject()
    let disposeBag = DisposeBag()

    override func awakeFromNib() {
        super.awakeFromNib()

        AnnotationsConfig.colors.forEach { hexColor in
            let circleView = ColorPickerCircleView(hexColor: hexColor)
            circleView.contentInsets = UIEdgeInsets(top: 6, left: 11, bottom: 6, right: 11)
            circleView.backgroundColor = .white
            circleView.tap.bind(to: self.colorChange).disposed(by: self.disposeBag)
            self.stackView.addArrangedSubview(circleView)
        }
    }

    func setup(selectedColor: String) {
        for view in self.stackView.arrangedSubviews {
            guard let circleView = view as? ColorPickerCircleView else { continue }
            circleView.isSelected = circleView.hexColor == selectedColor
        }
    }
}
