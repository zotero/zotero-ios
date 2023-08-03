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
    let valueObservable: PublishSubject<UInt>

    private(set) weak var button: UIButton!
    private weak var stepper: UIStepper!

    var value: UInt {
        get {
            return UInt(self.stepper.value)
        }

        set {
            self.stepper.value = Double(newValue)
            self.updateLabel(with: newValue)
        }
    }

    init(contentInsets: UIEdgeInsets) {
        self.contentInsets = contentInsets
        self.disposeBag = DisposeBag()
        self.tapObservable = PublishSubject()
        self.valueObservable = PublishSubject()
        super.init(frame: CGRect())
        self.setup()
    }

    required init?(coder: NSCoder) {
        self.contentInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        self.disposeBag = DisposeBag()
        self.tapObservable = PublishSubject()
        self.valueObservable = PublishSubject()
        super.init(coder: coder)
        self.setup()
    }

    // MARK: - Actions

    private func stepChanged() {
        let value = UInt(self.stepper.value)
        self.updateLabel(with: value)
        self.valueObservable.on(.next(value))
    }

    private func updateLabel(with value: UInt) {
        let valueString = "\(value)"
        let ptString = "pt"
        let attributedString = NSMutableAttributedString(string: valueString + ptString)
        attributedString.addAttributes([.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: UIColor.label], range: NSRange(location: 0, length: valueString.count))
        attributedString.addAttributes([.font: UIFont.preferredFont(forTextStyle: .callout), .foregroundColor: UIColor.darkGray], range: NSRange(location: valueString.count, length: ptString.count))
        self.button.setAttributedTitle(attributedString, for: .normal)
    }

    // MARK: - Setups

    private func setup() {
        let stepper = UIStepper()
        stepper.stepValue = 1
        stepper.minimumValue = 1
        stepper.maximumValue = 200
        stepper.rx.controlEvent(.valueChanged)
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { `self`, _ in
                self.stepChanged()
            })
            .disposed(by: self.disposeBag)
        self.stepper = stepper

        let button = UIButton()
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.rx.tap.bind(to: self.tapObservable).disposed(by: self.disposeBag)
        self.button = button

        let container = UIStackView(arrangedSubviews: [button, stepper])
        container.axis = .horizontal
        container.alignment = .center
        container.spacing = 12
        container.translatesAutoresizingMaskIntoConstraints = false

        self.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: self.topAnchor, constant: self.contentInsets.top),
            self.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: self.contentInsets.bottom),
            container.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: self.contentInsets.left),
            self.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: self.contentInsets.right)
        ])
    }
}
