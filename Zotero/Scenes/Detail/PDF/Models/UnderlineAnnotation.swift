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

        guard let comment = contents, !comment.isEmpty, !flags.contains(.hidden) else { return }
        CommentIconDrawingController.drawAnnotationComment(context: context, boundingBox: (rects?.first ?? boundingBox), color: (color ?? .black))
    }

    override func draw(context: CGContext, options: RenderOptions?) {
        super.draw(context: context, options: options)

        guard let comment = contents, !comment.isEmpty, !flags.contains(.hidden) else { return }
        CommentIconDrawingController.drawAnnotationComment(context: context, boundingBox: (rects?.first ?? boundingBox), color: (color ?? .black))
    }

    override class var supportsSecureCoding: Bool {
        true
    }
}
