//
//  FormattedTextView.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 1/8/24.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import RxSwift

final class FormattedTextView: TextKit1TextView {
    let attributedTextObservable: PublishSubject<NSAttributedString>
    let didBecomeActiveObservable: PublishSubject<Void>

    private let defaultFont: UIFont
    private let menuItems: [UIMenuItem]
    private let disposeBag: DisposeBag

    init(defaultFont: UIFont) {
        attributedTextObservable = PublishSubject()
        didBecomeActiveObservable = PublishSubject()
        self.defaultFont = defaultFont
        menuItems = createMenuItems()
        disposeBag = DisposeBag()
        super.init(frame: CGRect(), textContainer: nil)
        font = defaultFont
        setupObservers()

        func createMenuItems() -> [UIMenuItem] {
            let bold = UIMenuItem(title: "Bold", action: #selector(Self.toggleBoldface(_:)))
            let italics = UIMenuItem(title: "Italics", action: #selector(Self.toggleItalics(_:)))
            let superscript = UIMenuItem(title: "Superscript", action: #selector(Self.toggleSuperscript(_:)))
            let `subscript` = UIMenuItem(title: "Subscript", action: #selector(Self.toggleSubscript(_:)))
            return [bold, italics, superscript, `subscript`]
        }

        func setupObservers() {
            NotificationCenter.default
                .rx
                .notification(Self.textDidBeginEditingNotification, object: self)
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] _ in
                    guard let self else { return }
                    UIMenuController.shared.menuItems = menuItems
                    didBecomeActiveObservable.onNext(())
                })
                .disposed(by: disposeBag)

            NotificationCenter.default
                .rx
                .notification(Self.textDidChangeNotification, object: self)
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] _ in
                    guard let self else { return }
                    attributedTextObservable.onNext(attributedText)
                })
                .disposed(by: disposeBag)

            NotificationCenter.default
                .rx
                .notification(Self.textDidEndEditingNotification, object: self)
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { _ in
                    UIMenuController.shared.menuItems = nil
                })
                .disposed(by: disposeBag)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if sender is UIKeyCommand {
            switch action {
            case #selector(UIResponderStandardEditActions.toggleBoldface(_:)),
                #selector(UIResponderStandardEditActions.toggleItalics(_:)),
                #selector(Self.toggleSuperscript(_:)),
                #selector(Self.toggleSubscript(_:)):
                return isEditable

            default:
                break
            }
        }
        return super.canPerformAction(action, withSender: sender)
    }

    @objc func toggleSuperscript(_ sender: Any?) {
        guard selectedRange.length > 0 else { return }
        perform(attributedStringAction: { StringAttribute.toggleSuperscript(in: $0, range: $1, defaultFont: defaultFont) })
    }

    @objc func toggleSubscript(_ sender: Any?) {
        guard selectedRange.length > 0 else { return }
        perform(attributedStringAction: { StringAttribute.toggleSubscript(in: $0, range: $1, defaultFont: defaultFont) })
    }

    private func perform(attributedStringAction: (NSMutableAttributedString, NSRange) -> Void) {
        let range = selectedRange
        let string = NSMutableAttributedString(attributedString: attributedText)
        attributedStringAction(string, range)
        attributedText = string
        selectedRange = range
        attributedTextObservable.onNext(attributedText)
        delegate?.textViewDidChange?(self)
    }
}
