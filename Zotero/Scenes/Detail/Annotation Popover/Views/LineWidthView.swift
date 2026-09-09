//
//  LineWidthView.swift
//  Zotero
//
//  Created by Michal Rentka on 06.09.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class LineWidthView: UIView {
    struct Settings {
        let steps: [Float]
        let maxText: Float

        static var lineWidth: Settings {
            let steps: [Float] = Array(stride(from: Float(0.2), through: Float(1), by: Float(0.2))) + Array(stride(from: Float(1.5), through: Float(25), by: Float(0.5)))
            return .init(steps: steps, maxText: 25)
        }

        static var fontSize: Settings {
            return .init(steps: [6, 8, 10, 12, 14, 18, 24, 36, 48, 64, 72, 96, 144, 192], maxText: 144)
        }
    }

    enum Layout {
        case inline
        case stacked
    }

    private let contentInsets: UIEdgeInsets
    private let steps: [Float]
    private let layout: Layout

    private weak var titleLabel: UILabel!
    private weak var valueLabel: UILabel!
    private weak var slider: UISlider!
    private weak var minusButton: UIButton!
    private weak var plusButton: UIButton!

    var value: Float {
        get {
            let index = min(max(Int(slider.value.rounded()), 0), steps.count - 1)
            return steps[Int(index)]
        }

        set {
            let index = steps.enumerated().min(by: { abs($0.element - newValue) < abs($1.element - newValue) })?.offset ?? 0
            slider.value = Float(index)
            valueLabel.text = String(format: "%0.1f", steps[index])
            updateButtons()
        }
    }
    var valueObservable: Observable<Float> {
        return slider.rx.value.skip(1).map { [weak self] _ in
            return self?.value ?? 0
        }
    }

    init(title: String, settings: Settings, contentInsets: UIEdgeInsets, layout: Layout) {
        self.contentInsets = contentInsets
        steps = settings.steps
        self.layout = layout
        super.init(frame: CGRect())
        setup(title: title, settings: settings)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions

    private func updateButtons() {
        minusButton.isEnabled = slider.value > slider.minimumValue
        plusButton.isEnabled = slider.value < slider.maximumValue
    }

    // MARK: - Setups

    private func setup(title: String, settings: Settings) {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = Float(settings.steps.count - 1)
        slider.isContinuous = true
        slider.addAction(UIAction { [weak self] action in
            guard let slider = action.sender as? UISlider else { return }
            let roundedValue = slider.value.rounded()
            slider.value = roundedValue
            guard let self else { return }
            self.valueLabel.text = String(format: "%0.1f", value)
            updateButtons()
        }, for: .valueChanged)
        self.slider = slider

        let minusButton = UIButton(type: .system)
        minusButton.setImage(UIImage(systemName: "minus"), for: .normal)
        minusButton.setContentHuggingPriority(.required, for: .horizontal)
        minusButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        minusButton.addAction(UIAction { [weak slider] _ in
            guard let slider, slider.value > slider.minimumValue else { return }
            slider.value -= 1
            slider.sendActions(for: .valueChanged)
        }, for: .touchUpInside)
        self.minusButton = minusButton

        let plusButton = UIButton(type: .system)
        plusButton.setImage(UIImage(systemName: "plus"), for: .normal)
        plusButton.setContentHuggingPriority(.required, for: .horizontal)
        plusButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        plusButton.addAction(UIAction { [weak slider] _ in
            guard let slider, slider.value < slider.maximumValue else { return }
            slider.value += 1
            slider.sendActions(for: .valueChanged)
        }, for: .touchUpInside)
        self.plusButton = plusButton

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Asset.Colors.annotationText.color
        titleLabel.text = title
        self.titleLabel = titleLabel

        let valueLabel = UILabel()
        valueLabel.adjustsFontForContentSizeCategory = true
        let valueLabelFont: UIFont = .preferredFont(forTextStyle: .body)
        valueLabel.font = valueLabelFont
        valueLabel.textColor = .systemGray
        valueLabel.textAlignment = .right
        valueLabel.text = String(format: "%0.1f", value)
        // Set fixed width to that of the largest value so layout doesn't shift.
        let maxText = String(format: "%0.1f", settings.maxText)
        let maxWidth = (maxText as NSString).size(withAttributes: [.font: valueLabelFont]).width
        valueLabel.widthAnchor.constraint(equalToConstant: ceil(maxWidth) + 1.0).isActive = true
        self.valueLabel = valueLabel

        let controlsRow = UIStackView(arrangedSubviews: [minusButton, slider, plusButton])
        controlsRow.axis = .horizontal
        controlsRow.spacing = 12

        let container: UIStackView
        switch layout {
        case .inline:
            container = UIStackView(arrangedSubviews: [titleLabel, controlsRow, valueLabel])
            container.axis = .horizontal

        case .stacked:
            let spacer = UIView()
            spacer.setContentHuggingPriority(.fittingSizeLevel, for: .horizontal)
            let headerRow = UIStackView(arrangedSubviews: [titleLabel, spacer, valueLabel])
            headerRow.axis = .horizontal

            container = UIStackView(arrangedSubviews: [headerRow, controlsRow])
            container.axis = .vertical
            container.spacing = 12
        }

        container.spacing = 12
        container.translatesAutoresizingMaskIntoConstraints = false

        addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor, constant: contentInsets.top),
            bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: contentInsets.bottom),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInsets.left),
            trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: contentInsets.right)
        ])
    }
}
