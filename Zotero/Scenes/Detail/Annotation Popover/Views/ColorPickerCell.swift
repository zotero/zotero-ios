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

        self.accessibilityLabel = L10n.Accessibility.Pdf.colorPicker

        AnnotationsConfig.colors.forEach { hexColor in
            let circleView = ColorPickerCircleView(hexColor: hexColor)
            circleView.contentInsets = UIEdgeInsets(top: 11, left: 11, bottom: 11, right: 11)
            circleView.backgroundColor = .clear
            circleView.tap.bind(to: self.colorChange).disposed(by: self.disposeBag)
            circleView.backgroundColor = Asset.Colors.defaultCellBackground.color
            circleView.isAccessibilityElement = true
            self.stackView.addArrangedSubview(circleView)
        }
    }

    func setup(selectedColor: String) {
        for view in self.stackView.arrangedSubviews {
            guard let circleView = view as? ColorPickerCircleView else { continue }
            circleView.isSelected = circleView.hexColor == selectedColor
            circleView.accessibilityLabel = self.name(for: circleView.hexColor, isSelected: circleView.isSelected)
        }
    }

    private func name(for color: String, isSelected: Bool) -> String {
        let colorName = AnnotationsConfig.colorNames[color] ?? L10n.unknown
        return !isSelected ? colorName : L10n.Accessibility.Pdf.selected + ": " + colorName
    }
}
