//
//  HighlightAnnotation.swift
//  Zotero
//
//  Created by Michal Rentka on 10.12.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit

class HighlightAnnotation: PSPDFKit.HighlightAnnotation {
    override var shouldDrawNoteIconIfNeeded: Bool {
        return false
    }

    override func draw(context: CGContext, options: RenderOptions?) {
        super.draw(context: context, options: options)

        guard self.contents != nil else { return }

        CommentIconDrawingController.draw(context: context, boundingBox: (self.rects?.first ?? self.boundingBox), color: (self.color ?? .black))
    }
}
