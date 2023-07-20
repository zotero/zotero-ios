//
//  UnderlineAnnotation.swift
//  Zotero
//
//  Created by Michal Rentka on 18.07.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit

final class UnderlineAnnotation: PSPDFKit.UnderlineAnnotation {
    override var shouldDrawNoteIconIfNeeded: Bool {
        return false
    }

    override func lockAndRender(in context: CGContext, options: RenderOptions?) {
        super.lockAndRender(in: context, options: options)

        guard let comment = self.contents, !comment.isEmpty else { return }

        CommentIconDrawingController.draw(context: context, boundingBox: (self.rects?.first ?? self.boundingBox), color: (self.color ?? .black))
    }

    override func draw(context: CGContext, options: RenderOptions?) {
        super.draw(context: context, options: options)

        guard let comment = self.contents, !comment.isEmpty else { return }

        CommentIconDrawingController.draw(context: context, boundingBox: (self.rects?.first ?? self.boundingBox), color: (self.color ?? .black))
    }

    override class var supportsSecureCoding: Bool {
        true
    }
}
