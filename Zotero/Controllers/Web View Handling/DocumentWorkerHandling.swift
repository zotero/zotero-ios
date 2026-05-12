//
//  DocumentWorkerHandling.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 5/5/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

enum DocumentWorkerAction {
    case recognize(password: String?)
    case getFulltext(pages: [Int]?, password: String?)
    case getStructuredDocumentText(contentType: String, password: String?)

    var method: String {
        switch self {
        case .recognize:
            return "pdf.getRecognizerData"

        case .getFulltext:
            return "pdf.getFulltext"

        case .getStructuredDocumentText:
            return "getStructuredDocumentText"
        }
    }
}

enum DocumentWorkerOutput {
    case recognizerData(data: [String: Any])
    case fullText(data: [String: Any])
    case structuredDocumentText(data: [String: Any])
}

protocol DocumentWorkerHandling: AnyObject {
    var workFile: File? { get set }
    var shouldCacheWorkInput: Bool { get set }
    var observable: PublishSubject<(workId: String, result: Result<DocumentWorkerOutput, Swift.Error>)> { get }

    func supportsAction(_ action: DocumentWorkerAction) -> Bool
    func performAction(_ action: DocumentWorkerAction, workId: String)
}
