//
//  SquareAnnotation.swift
//  Zotero
//
//  Created by Michal Rentka on 06.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit

final class SquareAnnotation: PSPDFKit.SquareAnnotation {
    override var shouldDrawNoteIconIfNeeded: Bool {
        return false
    }

    override func draw(context: CGContext, options: RenderOptions?) {
        super.draw(context: context, options: options)

        guard let comment = self.contents, !comment.isEmpty else { return }

        CommentIconDrawingController.draw(context: context, boundingBox: self.boundingBox, color: (self.color ?? .black))
    }
}
