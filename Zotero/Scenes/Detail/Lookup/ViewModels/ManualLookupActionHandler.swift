//
//  ManualLookupActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 23.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

final class ManualLookupActionHandler: ViewModelActionHandler {
    typealias State = ManualLookupState
    typealias Action = ManualLookupAction

    private var doiRegex: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: #"10.\d{4,9}\/[-._;()\/:a-zA-Z0-9]+"#)
        } catch let error {
            DDLogError("LookupActionHandler: can't create doi expression - \(error)")
            return nil
        }
    }()

    init() {
    }

    func process(action: ManualLookupAction, in viewModel: ViewModel<ManualLookupActionHandler>) {
        switch action {
        case .processScannedText(let text):
            self.process(scannedText: text, in: viewModel)
        }
    }

    private func process(scannedText: String, in viewModel: ViewModel<ManualLookupActionHandler>) {
        var identifiers: [String] = []
        if let expression = self.doiRegex {
            identifiers = self.getResults(withExpression: expression, from: scannedText)
        }
        let isbns = ISBNParser.isbns(from: scannedText)
        if !isbns.isEmpty {
            identifiers.append(contentsOf: isbns)
        }

        guard !identifiers.isEmpty else { return }

        self.update(viewModel: viewModel) { state in
            state.scannedText = identifiers.joined(separator: ", ")
        }
    }

    private func getResults(withExpression expression: NSRegularExpression, from text: String) -> [String] {
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { result in
            let startIndex = text.index(text.startIndex, offsetBy: result.range.lowerBound)
            let endIndex = text.index(text.startIndex, offsetBy: result.range.upperBound)
            return String(text[startIndex..<endIndex])
        }
    }
}

