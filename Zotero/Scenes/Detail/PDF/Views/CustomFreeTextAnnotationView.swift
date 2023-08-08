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
    func showTagPicker(sender: UIView, key: PDFReaderState.AnnotationKey, updated: @escaping ([Tag]) -> Void)
    func deleteAnnotation(sender: UIView, key: PDFReaderState.AnnotationKey)
    func change(fontSize: UInt, for key: PDFReaderState.AnnotationKey)
    func getColor(for key: PDFReaderState.AnnotationKey) -> UIColor?
    func getFontSize(for key: PDFReaderState.AnnotationKey) -> UInt?
    func getTags(for key: PDFReaderState.AnnotationKey) -> [Tag]?
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

        let separator = UIView()
        separator.backgroundColor = .opaqueSeparator
        let separator2 = UIView()
        separator2.backgroundColor = .opaqueSeparator
        let separator3 = UIView()
        separator3.backgroundColor = .opaqueSeparator

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

        let colorButton = UIButton()
        let deleteButton = UIButton()

        if #available(iOS 15.0, *) {
            var colorConfiguration = UIButton.Configuration.plain()
            colorConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
            colorConfiguration.image = UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(scale: .large))
            colorButton.configuration = colorConfiguration

            var deleteConfiguration = UIButton.Configuration.plain()
            deleteConfiguration.image = UIImage(systemName: "trash", withConfiguration: UIImage.SymbolConfiguration(scale: .large))
            deleteConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
            deleteButton.configuration = deleteConfiguration
        } else {
            colorButton.setImage(UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(scale: .large)), for: .normal)
            colorButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)

            deleteButton.setImage(UIImage(systemName: "trash", withConfiguration: UIImage.SymbolConfiguration(scale: .large)), for: .normal)
            deleteButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        }

        colorButton.tintColor = self.delegate?.getColor(for: key) ?? Asset.Colors.zoteroBlueWithDarkMode.color
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

        // Can't use the Configuration API for tagButton because it ignores number of lines and just always adds multiple lines
        let tagButton = UIButton()
        tagButton.setAttributedTitle(self.attributedString(from: self.delegate?.getTags(for: key) ?? []), for: .normal)
        tagButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        tagButton.titleLabel?.numberOfLines = 1
        tagButton.titleLabel?.lineBreakMode = .byTruncatingTail
        tagButton.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        tagButton.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        tagButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tagButton.rx.tap
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { [weak tagButton] `self`, _ in
                guard let tagButton else { return }
                self.delegate?.showTagPicker(sender: tagButton, key: key, updated: { [weak tagButton] tags in
                    guard let tagButton else { return }
                    tagButton.setAttributedTitle(self.attributedString(from: tags), for: .normal)
                })
            })
            .disposed(by: self.disposeBag)

        deleteButton.tintColor = .red
        deleteButton.rx.tap
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { [weak deleteButton] `self`, _ in
                guard let deleteButton else { return }
                self.delegate?.deleteAnnotation(sender: deleteButton, key: key)
            })
            .disposed(by: self.disposeBag)

        let spacer = UIView()

        let container = UIStackView(arrangedSubviews: [sizePicker, spacer, separator, colorButton, separator2, tagButton, separator3, deleteButton])
        container.translatesAutoresizingMaskIntoConstraints = false
        container.spacing = 0
        container.alignment = .center
        self.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(greaterThanOrEqualTo: self.leadingAnchor, constant: 20),
            self.trailingAnchor.constraint(greaterThanOrEqualTo: container.trailingAnchor, constant: 20),
            container.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.topAnchor.constraint(equalTo: container.topAnchor),
            self.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            separator.heightAnchor.constraint(equalToConstant: 30),
            separator2.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            separator2.heightAnchor.constraint(equalToConstant: 30),
            separator3.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            separator3.heightAnchor.constraint(equalToConstant: 30),
            spacer.widthAnchor.constraint(equalToConstant: 20)
        ])
    }

    private func attributedString(from tags: [Tag]) -> NSAttributedString {
        if tags.isEmpty {
            return NSAttributedString(string: L10n.Pdf.AnnotationsSidebar.addTags, attributes: [.foregroundColor: Asset.Colors.zoteroBlueWithDarkMode.color])
        } else {
            return AttributedTagStringGenerator.attributedString(from: tags, limit: 3)
        }
    }

    @available(iOS 15, *)
    private func attributedString(from tags: [Tag]) -> AttributedString {
        if tags.isEmpty {
            var string = AttributedString(L10n.Pdf.AnnotationsSidebar.addTags)
            string.foregroundColor = Asset.Colors.zoteroBlueWithDarkMode.color
            return string
        } else {
            let nsAttributedString = AttributedTagStringGenerator.attributedString(from: tags, limit: 3)
            return (try? AttributedString(nsAttributedString, including: \.uiKit)) ?? AttributedString()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
