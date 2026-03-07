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

        static var lineWidth: Settings {
            let steps: [Float] = Array(stride(from: Float(0.2), through: Float(1.0), by: Float(0.2))) + Array(stride(from: Float(1.5), through: Float(25.0), by: Float(0.5)))
            return .init(steps: steps)
        }

        static var fontSize: Settings {
            return .init(steps: [6, 8, 10, 12, 14, 18, 24, 36, 48, 64, 72, 96, 144, 192])
        }
    }

    private let contentInsets: UIEdgeInsets
    private let steps: [Float]

    private weak var titleLabel: UILabel!
    private weak var valueLabel: UILabel!
    private weak var slider: UISlider!

    var value: Float {
        get {
            let index = min(max(Int(slider.value.rounded()), 0), steps.count - 1)
            return steps[Int(index)]
        }

        set {
            let index = steps.enumerated().min(by: { abs($0.element - newValue) < abs($1.element - newValue) })?.offset ?? 0
            slider.value = Float(index)
            valueLabel.text = String(format: "%0.1f", steps[index])
        }
    }
    var valueObservable: Observable<Float> {
        return slider.rx.value.skip(1).map { [weak self] _ in
            return self?.value ?? 0
        }
    }

    init(title: String, settings: Settings, contentInsets: UIEdgeInsets) {
        self.contentInsets = contentInsets
        steps = settings.steps
        super.init(frame: CGRect())
        setup(title: title, settings: settings)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        }, for: .valueChanged)
        self.slider = slider

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Asset.Colors.annotationText.color
        titleLabel.text = title
        self.titleLabel = titleLabel

        let valueLabel = UILabel()
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.font = .preferredFont(forTextStyle: .body)
        valueLabel.textColor = .systemGray
        valueLabel.text = String(format: "%0.1f", value)
        self.valueLabel = valueLabel

        let container = UIStackView(arrangedSubviews: [titleLabel, slider, valueLabel])
        container.axis = .horizontal
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
