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
    private let delegateProxy: FormattedTextViewDelegateProxy
    private let disposeBag: DisposeBag

    /// Routes the delegate through `delegateProxy`, which injects the custom formatting actions into the edit menu
    /// (replacement for the deprecated `UIMenuItem` / `UIMenuController` API) and forwards all other callbacks to the assigned delegate.
    override var delegate: UITextViewDelegate? {
        // Must return the proxy (the actual delegate), not `forwardingDelegate` — UIKit reads this getter to dispatch delegate calls (e.g. the edit menu), so returning anything else routes messages to an object that doesn't implement them.
        get { super.delegate }
        set {
            delegateProxy.forwardingDelegate = newValue
            // Reassign the proxy so UITextView re-evaluates which delegate methods are implemented (it caches `responds(to:)` on assignment).
            super.delegate = nil
            super.delegate = delegateProxy
        }
    }

    init(defaultFont: UIFont) {
        attributedTextObservable = PublishSubject()
        didBecomeActiveObservable = PublishSubject()
        self.defaultFont = defaultFont
        delegateProxy = FormattedTextViewDelegateProxy()
        disposeBag = DisposeBag()
        super.init(frame: CGRect(), textContainer: nil)
        font = defaultFont
        super.delegate = delegateProxy
        setupObservers()

        func setupObservers() {
            NotificationCenter.default
                .rx
                .notification(Self.textDidBeginEditingNotification, object: self)
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] _ in
                    guard let self else { return }
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
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Adds custom formatting actions to the system menu that contains Bold and Italics.
    fileprivate static func addingFormattingActions(to elements: [UIMenuElement], for textView: FormattedTextView) -> [UIMenuElement] {
        return elements.map { element in
            guard let menu = element as? UIMenu else { return element }

            if menu.identifier == .textStyle {
                return menu.replacingChildren(menu.children + formattingMenuElements(for: textView))
            }

            let children = addingFormattingActions(to: menu.children, for: textView)
            guard !menu.children.elementsEqual(children, by: { $0 === $1 }) else { return menu }
            return menu.replacingChildren(children)
        }

        func formattingMenuElements(for textView: FormattedTextView) -> [UIMenuElement] {
            return [
                UIAction(title: "Superscript") { [weak textView] _ in textView?.toggleSuperscript(nil) },
                UIAction(title: "Subscript") { [weak textView] _ in textView?.toggleSubscript(nil) }
            ]
        }
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

/// Forwards all `UITextViewDelegate` callbacks to `forwardingDelegate`, while injecting `FormattedTextView`'s custom formatting actions into the edit menu.
private final class FormattedTextViewDelegateProxy: NSObject, UITextViewDelegate {
    weak var forwardingDelegate: UITextViewDelegate?

    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        // Let the forwarding delegate provide its own menu first, otherwise fall back to the suggested actions.
        let baseActions = forwardingDelegate?.textView?(textView, editMenuForTextIn: range, suggestedActions: suggestedActions)?.children ?? suggestedActions
        guard let textView = textView as? FormattedTextView, textView.isEditable else {
            return baseActions.isEmpty ? nil : UIMenu(children: baseActions)
        }
        return UIMenu(children: FormattedTextView.addingFormattingActions(to: baseActions, for: textView))
    }

    // Forward every other (optional) delegate method to the real delegate.

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (forwardingDelegate?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if forwardingDelegate?.responds(to: aSelector) == true {
            return forwardingDelegate
        }
        return super.forwardingTarget(for: aSelector)
    }
}
