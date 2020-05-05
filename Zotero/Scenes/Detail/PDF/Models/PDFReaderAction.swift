//
//  PDFReaderAction.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum PDFReaderAction {
    case loadAnnotations
    case searchAnnotations(String)
    case selectAnnotation(Annotation?)
    case selectAnnotationFromDocument(key: String, page: Int)
}
