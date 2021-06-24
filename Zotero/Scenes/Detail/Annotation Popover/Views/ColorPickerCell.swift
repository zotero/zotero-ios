//
//  ColorPickerCell.swift
//  Zotero
//
//  Created by Michal Rentka on 27.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class ColorPickerCell: UITableViewCell {
    @IBOutlet private weak var stackView: UIStackView!

    let colorChange: PublishSubject<String> = PublishSubject()
    let disposeBag = DisposeBag()

    override func awakeFromNib() {
        super.awakeFromNib()

        AnnotationsConfig.colors.forEach { hexColor in
            let circleView = ColorPickerCircleView(hexColor: hexColor)
            circleView.contentInsets = UIEdgeInsets(top: 11, left: 11, bottom: 11, right: 11)
            circleView.backgroundColor = .clear
            circleView.tap.bind(to: self.colorChange).disposed(by: self.disposeBag)
            circleView.backgroundColor = Asset.Colors.defaultCellBackground.color
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
