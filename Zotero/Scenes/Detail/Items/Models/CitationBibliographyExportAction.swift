//
//  CitationBibliographyExportAction.swift
//  Zotero
//
//  Created by Michal Rentka on 29.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum CitationBibliographyExportAction {
    case setType(CitationBibliographyExportState.Kind)
    case setMode(CitationBibliographyExportState.OutputMode)
    case setMethod(CitationBibliographyExportState.OutputMethod)
}
