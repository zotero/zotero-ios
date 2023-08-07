//
//  CustomFreeTextAnnotationView.swift
//  Zotero
//
//  Created by Michal Rentka on 02.08.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit
import PSPDFKitUI
import RxSwift

protocol FreeTextInputDelegate: AnyObject {
    func showColorPicker(sender: UIView, key: PDFReaderState.AnnotationKey, updated: @escaping (String) -> Void)
    func showFontSizePicker(sender: UIView, key: PDFReaderState.AnnotationKey, updated: @escaping (UInt) -> Void)
    func change(fontSize: UInt, for key: PDFReaderState.AnnotationKey)
    func getColor(for key: PDFReaderState.AnnotationKey) -> UIColor?
    func getFontSize(for key: PDFReaderState.AnnotationKey) -> UInt?
}

final class CustomFreeTextAnnotationView: FreeTextAnnotationView {
    var annotationKey: PDFReaderState.AnnotationKey?
    weak var delegate: FreeTextInputDelegate?

    override func textViewForEditing() -> UITextView {
        let textView = super.textViewForEditing()
        if let annotationKey, let delegate {
            let view = FreeTextInputAccessory(key: annotationKey, delegate: delegate)
            textView.inputAccessoryView = view
        }
        return textView
    }
}

final class FreeTextInputAccessory: UIView {
    private weak var delegate: FreeTextInputDelegate?
    private let disposeBag: DisposeBag

    init(key: PDFReaderState.AnnotationKey, delegate: FreeTextInputDelegate) {
        self.delegate = delegate
        self.disposeBag = DisposeBag()
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        self.autoresizingMask = .flexibleWidth
        self.backgroundColor = .systemBackground

        let sizePicker = FontSizeView(contentInsets: UIEdgeInsets.zero)
        sizePicker.value = delegate.getFontSize(for: key) ?? 0
        sizePicker.valueObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { `self`, value in
                self.delegate?.change(fontSize: value, for: key)
            })
            .disposed(by: self.disposeBag)
        sizePicker.tapObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { [weak sizePicker] `self`, _ in
                guard let sizePicker else { return }
                self.delegate?.showFontSizePicker(sender: sizePicker, key: key, updated: { [weak sizePicker] size in
                    guard let sizePicker else { return }
                    sizePicker.value = size
                })
            })
            .disposed(by: self.disposeBag)

        let separator = UIView()
        separator.backgroundColor = .opaqueSeparator

        let colorButton = UIButton()
        colorButton.tintColor = self.delegate?.getColor(for: key) ?? Asset.Colors.zoteroBlueWithDarkMode.color
        colorButton.setImage(UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(scale: .large)), for: .normal)
        colorButton.rx.tap
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { [weak colorButton] `self`, _ in
                guard let colorButton else { return }
                self.delegate?.showColorPicker(sender: colorButton, key: key, updated: { [weak colorButton] color in
                    guard let colorButton else { return }
                    colorButton.tintColor = UIColor(hex: color)
                })
            })
            .disposed(by: self.disposeBag)

        let container = UIStackView(arrangedSubviews: [sizePicker, separator, colorButton])
        container.translatesAutoresizingMaskIntoConstraints = false
        container.spacing = 20
        container.alignment = .center
        self.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(greaterThanOrEqualTo: self.leadingAnchor),
            self.trailingAnchor.constraint(greaterThanOrEqualTo: container.trailingAnchor),
            container.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.topAnchor.constraint(equalTo: container.topAnchor),
            self.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            separator.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
