//
//  PDFSettingsState.swift
//  Zotero
//
//  Created by Michal Rentka on 01.03.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import PSPDFKit

struct PDFSettingsState: ViewModelState {
    var settings: PDFSettings

    init(settings: PDFSettings) {
        self.settings = settings
    }

    func cleanup() {}
}

#endif
