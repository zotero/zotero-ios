//
//  PDFExportState.swift
//  Zotero
//
//  Created by Michal Rentka on 26.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum PDFExportState {
    case preparing
    case exported(File)
    case failed(PDFDocumentExporter.Error)
}
