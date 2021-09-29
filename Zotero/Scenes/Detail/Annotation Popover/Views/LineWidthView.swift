//
//  LineWidthView.swift
//  Zotero
//
//  Created by Michal Rentka on 06.09.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift
import RxCocoa

final class LineWidthView: UIView {
    struct Settings {
        let minValue: Float
        let maxValue: Float
        let stepFunction: (Float) -> Float

        static var `default`: Settings {
            return Settings(minValue: 1, maxValue: 10, stepFunction: { $0 })
        }

        static var lineWidth: Settings {
            return LineWidthView.Settings(minValue: 0.2, maxValue: 25, stepFunction: { value in
                if value < 1 {
                    return value.rounded(to: 1)
                }
                if value < 10 {
                    return ceil(value * 2) / 2
                }
                return ceil(value)
            })
        }
    }

    private let stepFunction: (Float) -> Float
    private let disposeBag: DisposeBag

    private weak var valueLabel: UILabel!
    private weak var slider: UISlider!

    var value: Float {
        get {
            return self.slider.value
        }

        set {
            self.step(value: newValue)
        }
    }
    var valueObservable: ControlProperty<Float> { return self.slider.rx.value }

    init(settings: Settings) {
        self.stepFunction = settings.stepFunction
        self.disposeBag = DisposeBag()
        super.init(frame: CGRect())
        self.setup(settings: settings)
    }

    required init?(coder: NSCoder) {
        let settings = Settings.default
        self.stepFunction = settings.stepFunction
        self.disposeBag = DisposeBag()
        super.init(coder: coder)
        self.setup(settings: settings)
    }

    // MARK: - Actions

    private func step(value: Float) {
        self.slider.value = self.stepFunction(value)
        self.valueLabel.text = String(format: "%0.1f", self.slider.value)
    }

    // MARK: - Setups

    private func setup(settings: Settings) {
        let slider = UISlider()
        slider.minimumValue = settings.minValue
        slider.maximumValue = settings.maxValue
        slider.rx.value.skip(1).subscribe(with: self, onNext: { `self`, value in
            self.step(value: value)
        })
        .disposed(by: self.disposeBag)
        self.slider = slider

        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .systemGray
        label.text = String(format: "%0.1f", self.slider.value)
        self.valueLabel = label

        let container = UIStackView(arrangedSubviews: [slider, label])
        container.axis = .horizontal
        container.spacing = 12
        container.translatesAutoresizingMaskIntoConstraints = false

        self.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
            self.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: 8),
            container.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 16),
            self.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 16)
        ])
    }
}
