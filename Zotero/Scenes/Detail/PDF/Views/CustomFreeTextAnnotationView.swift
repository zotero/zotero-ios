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
    func showColorPicker(sender: UIView, key: PDFReaderState.AnnotationKey)
    func showFontSizePicker(sender: UIView, key: PDFReaderState.AnnotationKey)
    func change(fontSize: UInt, for key: PDFReaderState.AnnotationKey)
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
                self.delegate?.showFontSizePicker(sender: sizePicker, key: key)
            })
            .disposed(by: self.disposeBag)

        let container = UIStackView(arrangedSubviews: [sizePicker])
        container.translatesAutoresizingMaskIntoConstraints = false
        container.spacing = 8
        container.alignment = .center
        self.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(greaterThanOrEqualTo: self.leadingAnchor),
            self.trailingAnchor.constraint(greaterThanOrEqualTo: container.trailingAnchor),
            container.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.topAnchor.constraint(equalTo: container.topAnchor),
            self.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sizePicker.widthAnchor.constraint(equalToConstant: 200)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
