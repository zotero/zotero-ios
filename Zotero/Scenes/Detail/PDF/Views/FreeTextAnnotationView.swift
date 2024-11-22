//
//  FreeTextAnnotationView.swift
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
    func showFontSizePicker(sender: UIView, key: PDFReaderState.AnnotationKey, updated: @escaping (CGFloat) -> Void)
    func showTagPicker(sender: UIView, key: PDFReaderState.AnnotationKey, updated: @escaping ([Tag]) -> Void)
    func deleteAnnotation(sender: UIView, key: PDFReaderState.AnnotationKey)
    func change(fontSize: CGFloat, for key: PDFReaderState.AnnotationKey)
    func getColor(for key: PDFReaderState.AnnotationKey) -> UIColor?
    func getFontSize(for key: PDFReaderState.AnnotationKey) -> CGFloat?
    func getTags(for key: PDFReaderState.AnnotationKey) -> [Tag]?
}

final class FreeTextAnnotationView: PSPDFKitUI.FreeTextAnnotationView {
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
    private weak var sizePicker: FontSizeView?
    private let disposeBag: DisposeBag

    init(key: PDFReaderState.AnnotationKey, delegate: FreeTextInputDelegate) {
        self.delegate = delegate
        disposeBag = DisposeBag()
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        autoresizingMask = .flexibleWidth
        backgroundColor = .systemBackground

        let separator = UIView()
        separator.backgroundColor = .opaqueSeparator
        let separator2 = UIView()
        separator2.backgroundColor = .opaqueSeparator
        let separator3 = UIView()
        separator3.backgroundColor = .opaqueSeparator

        let sizePicker = FontSizeView(contentInsets: UIEdgeInsets.zero, stepperEnabled: traitCollection.horizontalSizeClass != .compact)
        sizePicker.value = delegate.getFontSize(for: key) ?? 0
        self.sizePicker = sizePicker
        sizePicker.valueObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak delegate] value in
                delegate?.change(fontSize: value, for: key)
            })
            .disposed(by: disposeBag)
        sizePicker.tapObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak delegate, weak sizePicker] _ in
                guard let delegate, let sizePicker else { return }
                delegate.showFontSizePicker(sender: sizePicker, key: key, updated: { [weak sizePicker] size in
                    sizePicker?.value = size
                })
            })
            .disposed(by: disposeBag)

        let colorButton = UIButton()
        var colorConfiguration = UIButton.Configuration.plain()
        colorConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
        colorConfiguration.image = UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(scale: .large))
        colorButton.configuration = colorConfiguration

        let deleteButton = UIButton()
        var deleteConfiguration = UIButton.Configuration.plain()
        deleteConfiguration.image = UIImage(systemName: "trash", withConfiguration: UIImage.SymbolConfiguration(scale: .large))
        deleteConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
        deleteButton.configuration = deleteConfiguration

        colorButton.tintColor = delegate.getColor(for: key) ?? Asset.Colors.zoteroBlueWithDarkMode.color
        colorButton.rx.tap
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak delegate, weak colorButton] _ in
                guard let delegate, let colorButton else { return }
                delegate.showColorPicker(sender: colorButton, key: key, updated: { [weak colorButton] color in
                    colorButton?.tintColor = UIColor(hex: color)
                })
            })
            .disposed(by: disposeBag)

        // Can't use the Configuration API for tagButton because it ignores number of lines and just always adds multiple lines
        let tagButton = UIButton()
        tagButton.setAttributedTitle(attributedString(from: delegate.getTags(for: key) ?? []), for: .normal)
        tagButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        tagButton.titleLabel?.numberOfLines = 1
        tagButton.titleLabel?.lineBreakMode = .byTruncatingTail
        tagButton.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        tagButton.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        tagButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tagButton.rx.tap
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self, weak tagButton] _ in
                guard let self, let tagButton else { return }
                self.delegate?.showTagPicker(sender: tagButton, key: key, updated: { [weak self, weak tagButton] tags in
                    guard let self, let tagButton else { return }
                    tagButton.setAttributedTitle(attributedString(from: tags), for: .normal)
                })
            })
            .disposed(by: disposeBag)

        deleteButton.tintColor = .red
        deleteButton.rx.tap
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak delegate, weak deleteButton] _ in
                guard let delegate, let deleteButton else { return }
                delegate.deleteAnnotation(sender: deleteButton, key: key)
            })
            .disposed(by: disposeBag)

        let spacer = UIView()

        let container = UIStackView(arrangedSubviews: [sizePicker, spacer, separator, colorButton, separator2, tagButton, separator3, deleteButton])
        container.translatesAutoresizingMaskIntoConstraints = false
        container.spacing = 0
        container.alignment = .center
        addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            trailingAnchor.constraint(greaterThanOrEqualTo: container.trailingAnchor, constant: 20),
            container.centerXAnchor.constraint(equalTo: centerXAnchor),
            topAnchor.constraint(equalTo: container.topAnchor),
            bottomAnchor.constraint(equalTo: container.bottomAnchor),
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

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        sizePicker?.stepperEnabled = traitCollection.horizontalSizeClass != .compact
    }
}
