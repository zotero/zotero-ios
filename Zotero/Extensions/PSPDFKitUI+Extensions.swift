//
//  PSPDFKitUI+Extensions.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 28/2/24.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import PSPDFKitUI

extension PSPDFKitUI.PDFViewController {
    open override var keyCommands: [UIKeyCommand]? {
        var keyCommands: [UIKeyCommand] = []

        let previousInput: String
        let nextInput: String
        switch configuration.scrollDirection {
        case .horizontal:
            previousInput = UIKeyCommand.inputLeftArrow
            nextInput = UIKeyCommand.inputRightArrow

        case .vertical:
            previousInput = UIKeyCommand.inputUpArrow
            nextInput = UIKeyCommand.inputDownArrow
        }
        let pageCommands: [UIKeyCommand] = [
            .init(title: L10n.Pdf.previousPage, action: #selector(previousPageAction), input: previousInput),
            .init(title: L10n.Pdf.nextPage, action: #selector(nextPageAction), input: nextInput)
        ]
        pageCommands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        let viewportCommands: [UIKeyCommand] = [
            .init(title: L10n.Pdf.previousViewport, action: #selector(previousViewportAction), input: previousInput, modifierFlags: [.alternate]),
            .init(title: L10n.Pdf.nextViewport, action: #selector(nextViewportAction), input: nextInput, modifierFlags: [.alternate])
        ]
        keyCommands += pageCommands + viewportCommands

        return keyCommands
    }

    open override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(previousPageAction), #selector(nextPageAction), #selector(previousViewportAction), #selector(nextViewportAction):
            return true

        default:
            return false
        }
    }

    @objc private func previousPageAction() {
        documentViewController?.scrollToPreviousPageMiddle(animated: true)
    }

    @objc private func nextPageAction() {
        documentViewController?.scrollToNextPageMiddle(animated: true)
    }

    @objc private func previousViewportAction() {
        documentViewController?.scrollToPreviousViewport(animated: true, fallbackToSpread: true)
    }

    @objc private func nextViewportAction() {
        documentViewController?.scrollToNextViewport(animated: true, fallbackToSpread: true)
    }
}

extension PSPDFKitUI.PDFDocumentViewController {
    func scrollToPreviousPageMiddle(animated: Bool) {
        let previousContinuousSpreadIndex = floor(continuousSpreadIndex - 1) + 0.5
        guard previousContinuousSpreadIndex >= 0 else { return }
        setContinuousSpreadIndex(previousContinuousSpreadIndex, animated: animated)
    }

    func scrollToNextPageMiddle(animated: Bool) {
        let nextContinuousSpreadIndex = floor(continuousSpreadIndex + 1) + 0.5
        setContinuousSpreadIndex(nextContinuousSpreadIndex, animated: animated)
    }

    @discardableResult
    func scrollToPreviousViewport(animated: Bool, fallbackToSpread: Bool = true) -> Bool {
        let scrolled = scrollToPreviousViewport(animated: animated)
        guard !scrolled && fallbackToSpread else {
            return scrolled
        }
        // Viewport didn't scroll, this may happen if the page is not zoomed. Scroll by spread instead.
        return scrollToPreviousSpread(animated: animated)
    }

    @discardableResult
    func scrollToNextViewport(animated: Bool, fallbackToSpread: Bool = true) -> Bool {
        let scrolled = scrollToNextViewport(animated: animated)
        guard !scrolled && fallbackToSpread else {
            return scrolled
        }
        // Viewport didn't scroll, this may happen if page is not zoomed. Scroll by spread instead.
        return scrollToNextSpread(animated: animated)
    }
}
