//
//  FontSizeView.swift
//  Zotero
//
//  Created by Michal Rentka on 31.07.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift
import RxCocoa

final class FontSizeView: UIView {
    private let contentInsets: UIEdgeInsets
    private let disposeBag: DisposeBag
    let tapObservable: PublishSubject<()>
    let valueObservable: PublishSubject<CGFloat>

    var stepperEnabled: Bool {
        didSet {
            stepper.isHidden = !stepperEnabled
        }
    }
    private(set) weak var button: UIButton!
    private weak var stepper: UIStepper!

    var value: CGFloat {
        get {
            return CGFloat(stepper.value)
        }

        set {
            stepper.value = Double(newValue)
            updateLabel(with: newValue)
        }
    }

    init(contentInsets: UIEdgeInsets, stepperEnabled: Bool) {
        self.contentInsets = contentInsets
        self.stepperEnabled = stepperEnabled
        disposeBag = DisposeBag()
        tapObservable = PublishSubject()
        valueObservable = PublishSubject()
        super.init(frame: CGRect())
        setup()
    }

    required init?(coder: NSCoder) {
        contentInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        stepperEnabled = true
        disposeBag = DisposeBag()
        tapObservable = PublishSubject()
        valueObservable = PublishSubject()
        super.init(coder: coder)
        setup()
    }

    // MARK: - Actions

    private func stepChanged() {
        let value = CGFloat(stepper.value)
        updateLabel(with: value)
        valueObservable.on(.next(value))
    }

    private func updateLabel(with value: CGFloat) {
        let valueString = "\(value)"
        let ptString = "pt"
        let attributedString = NSMutableAttributedString(string: valueString + ptString)
        attributedString.addAttributes([.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: UIColor.label], range: NSRange(location: 0, length: valueString.count))
        attributedString.addAttributes([.font: UIFont.preferredFont(forTextStyle: .callout), .foregroundColor: UIColor.darkGray], range: NSRange(location: valueString.count, length: ptString.count))
        button.setAttributedTitle(attributedString, for: .normal)
    }

    // MARK: - Setups

    private func setup() {
        let stepper = UIStepper()
        stepper.isHidden = !stepperEnabled
        stepper.stepValue = 0.5
        stepper.minimumValue = 1
        stepper.maximumValue = 200
        stepper.rx.controlEvent(.valueChanged)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] _ in
                self?.stepChanged()
            })
            .disposed(by: disposeBag)
        self.stepper = stepper

        let button = UIButton()
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.rx.tap.bind(to: tapObservable).disposed(by: disposeBag)
        self.button = button

        let container = UIStackView(arrangedSubviews: [button, stepper])
        container.axis = .horizontal
        container.alignment = .center
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
