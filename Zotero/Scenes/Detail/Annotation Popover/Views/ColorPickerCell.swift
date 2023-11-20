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
    let colorChange: PublishSubject<String>
    private(set) var disposeBag: DisposeBag

    private var colorPicker: ColorPickerStackView?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        colorChange = PublishSubject()
        disposeBag = DisposeBag()
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
        selectionStyle = .none
        accessibilityLabel = L10n.Accessibility.Pdf.colorPicker

        func setup() {
            let hexColors = AnnotationsConfig.allColors
            let colorPicker = ColorPickerStackView(
                hexColors: hexColors,
                columnsDistribution: UIDevice.current.userInterfaceIdiom == .pad ? .fixed(numberOfColumns: hexColors.count) : .fitInWidth(width: UIScreen.main.bounds.width),
                allowsMultipleSelection: false,
                circleBackgroundColor: .secondarySystemGroupedBackground,
                circleContentInsets: UIEdgeInsets(top: 11, left: 11, bottom: 11, right: 11),
                accessibilityLabelProvider: { hexColor, isSelected in
                    name(for: hexColor, isSelected: isSelected)
                },
                hexColorToggled: { [weak self] hexColor in
                    self?.colorChange.onNext(hexColor)
                }
            )
            colorPicker.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(colorPicker)
            self.colorPicker = colorPicker

            NSLayoutConstraint.activate([
                colorPicker.topAnchor.constraint(equalTo: contentView.topAnchor),
                colorPicker.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                colorPicker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
                colorPicker.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -5)
            ])

            func name(for color: String, isSelected: Bool) -> String {
                let colorName = AnnotationsConfig.colorNames[color] ?? L10n.unknown
                return !isSelected ? colorName : L10n.Accessibility.Pdf.selected + ": " + colorName
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        disposeBag = DisposeBag()
    }

    func setup(selectedColor: String, annotationType: AnnotationType) {
        guard let colorPicker else { return }
        let colors = AnnotationsConfig.colors(for: annotationType)
        for view in colorPicker.arrangedSubviews {
            guard let colorRow = view as? UIStackView else { continue }
            for view in colorRow.arrangedSubviews {
                guard let circleView = view as? ColorPickerCircleView else { continue }
                circleView.isHidden = !colors.contains(circleView.hexColor)
            }
        }
        colorPicker.setSelected(hexColor: selectedColor)
    }
}
