//
//  SquareAnnotation.swift
//  Zotero
//
//  Created by Michal Rentka on 06.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit

class SquareAnnotation: PSPDFKit.SquareAnnotation {
    override var shouldDrawNoteIconIfNeeded: Bool {
        return false
    }
}
