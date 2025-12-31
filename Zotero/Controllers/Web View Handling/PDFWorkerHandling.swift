//
//  PDFWorkerHandling.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 30/12/25.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import RxSwift

enum PDFWorkerData {
    case recognizerData(data: [String: Any])
    case fullText(data: [String: Any])
}

protocol PDFWorkerHandling: AnyObject {
    var workFile: File? { get set }
    var shouldCacheWorkData: Bool { get set }
    var observable: PublishSubject<(workId: String, result: Result<PDFWorkerData, Swift.Error>)> { get }

    func recognize(workId: String)
    func getFullText(pages: [Int]?, workId: String)
}
