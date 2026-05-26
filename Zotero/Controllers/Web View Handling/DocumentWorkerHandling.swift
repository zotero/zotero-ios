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
    case recognizePDF(password: String?)
    case getPDFFulltext(pages: [Int]?, password: String?)
    case getStructuredDocumentText(contentType: String, password: String?, sourceHash: String)

    var method: String {
        switch self {
        case .recognizePDF:
            return "pdf.getRecognizerData"

        case .getPDFFulltext:
            return "pdf.getFulltext"

        case .getStructuredDocumentText:
            return "getStructuredDocumentTextJSON"
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
