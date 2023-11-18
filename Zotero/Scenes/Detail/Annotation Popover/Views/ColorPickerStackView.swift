//
//  ColorPickerStackView.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 18/11/23.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class ColorPickerStackView: UIStackView {
    enum ColumnsDistribution {
        case fixed(numberOfColumns: Int)
        case fitInWidth(width: CGFloat)
    }

    let hexColors: [String]
    let columnsDistribution: ColumnsDistribution
    let allowsMultipleSelection: Bool
    let circleBackgroundColor: UIColor
    let circleSize: CGFloat
    let circleOffset: CGFloat
    let circleSelectionLineWidth: CGFloat
    let circleSelectionInset: UIEdgeInsets
    let circleContentInsets: UIEdgeInsets
    let trailingSpacerViewProvider: () -> UIView?
    let accessibilityLabelProvider: (_ hexColor: String, _ isSelected: Bool) -> String?
    let hexColorToggled: (_ hexColor: String) -> Void
    private let disposeBag: DisposeBag

    init(
        hexColors: [String],
        columnsDistribution: ColumnsDistribution,
        allowsMultipleSelection: Bool,
        circleBackgroundColor: UIColor,
        circleSize: CGFloat = 22,
        circleOffset: CGFloat = .zero,
        circleSelectionLineWidth: CGFloat = 1.5,
        circleSelectionInset: UIEdgeInsets = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2),
        circleContentInsets: UIEdgeInsets = .zero,
        trailingSpacerViewProvider: @escaping () -> UIView? = { nil },
        accessibilityLabelProvider: @escaping (_ hexColor: String, _ isSelected: Bool) -> String? = { _, _ in nil },
        hexColorToggled: @escaping (_ hexColor: String) -> Void
    ) {
        self.hexColors = hexColors
        self.columnsDistribution = columnsDistribution
        self.allowsMultipleSelection = allowsMultipleSelection
        self.circleBackgroundColor = circleBackgroundColor
        self.circleSize = circleSize
        self.circleOffset = circleOffset
        self.circleSelectionLineWidth = circleSelectionLineWidth
        self.circleSelectionInset = circleSelectionInset
        self.circleContentInsets = circleContentInsets
        self.trailingSpacerViewProvider = trailingSpacerViewProvider
        self.accessibilityLabelProvider = accessibilityLabelProvider
        self.hexColorToggled = hexColorToggled
        disposeBag = DisposeBag()
        super.init(frame: .zero)

        setup()

        func setup() {
            spacing = circleOffset
            axis = .vertical

            let columns = idealNumberOfColumns()
            let rows = Int(ceil(Float(hexColors.count) / Float(columns)))

            for idx in 0..<rows {
                let offset = idx * columns
                var colorViews: [UIView] = []

                for idy in 0..<columns {
                    let id = offset + idy
                    if id >= hexColors.count {
                        break
                    }

                    let hexColor = hexColors[id]
                    let circleView = ColorPickerCircleView(hexColor: hexColor)
                    circleView.backgroundColor = circleBackgroundColor
                    circleView.circleSize = CGSize(width: circleSize, height: circleSize)
                    circleView.selectionLineWidth = circleSelectionLineWidth
                    circleView.selectionInset = circleSelectionInset
                    circleView.contentInsets = circleContentInsets
                    circleView.isAccessibilityElement = true
                    circleView.accessibilityLabel = accessibilityLabelProvider(hexColor, false)
                    circleView.tap
                        .observe(on: MainScheduler.instance)
                        .subscribe(onNext: { [weak self] _ in
                            self?.hexColorToggled(hexColor)
                        })
                        .disposed(by: disposeBag)
                    colorViews.append(circleView)
                }

                if let trailingSpacerView = trailingSpacerViewProvider() {
                    colorViews.append(trailingSpacerView)
                }

                let colorRow = UIStackView(arrangedSubviews: colorViews)
                colorRow.distribution = .fill
                colorRow.spacing = circleOffset
                colorRow.axis = .horizontal
                addArrangedSubview(colorRow)
            }

            func idealNumberOfColumns() -> Int {
                switch columnsDistribution {
                case .fixed(let numberOfColumns):
                    return numberOfColumns

                case .fitInWidth(let width):
                    // Calculate number of circles which fit in whole screen width
                    return Int(width / (circleSize + circleOffset + circleContentInsets.left + circleContentInsets.right))
                }
            }
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var selectedHexColors: [String] {
        var selectedHexColors: [String] = []
        for view in arrangedSubviews {
            guard let colorRow = view as? UIStackView else { continue }
            for view in colorRow.arrangedSubviews {
                guard let pickerView = view as? ColorPickerCircleView else { continue }
                if pickerView.isSelected {
                    selectedHexColors.append(pickerView.hexColor)
                }
            }
        }
        return selectedHexColors
    }

    var selectedHexColor: String? {
        selectedHexColors.first
    }

    func setSelected(hexColors: [String]) {
        for view in arrangedSubviews {
            guard let colorRow = view as? UIStackView else { continue }
            for view in colorRow.arrangedSubviews {
                guard let circleView = view as? ColorPickerCircleView else { continue }
                let isSelected: Bool
                if allowsMultipleSelection {
                    isSelected = hexColors.contains(circleView.hexColor)
                } else {
                    isSelected = hexColors.first == circleView.hexColor
                }
                circleView.isSelected = isSelected
                circleView.accessibilityLabel = accessibilityLabelProvider(circleView.hexColor, isSelected)
            }
        }
    }

    func setSelected(hexColor: String?) {
        if let hexColor {
            setSelected(hexColors: [hexColor])
        } else {
            setSelected(hexColors: [])
        }
    }
}
