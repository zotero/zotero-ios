//
//  NoteAnnotation.swift
//  Zotero
//
//  Created by Michal Rentka on 11.12.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import PSPDFKit

final class NoteAnnotation: PSPDFKit.NoteAnnotation {
    override var fixedSize: CGSize {
        return AnnotationsConfig.noteAnnotationSize
    }

    override func drawImage(in context: CGContext, boundingBox: CGRect, options: RenderOptions?) {
        guard let color else { return }
        CommentIconDrawingController.drawNoteAnnotation(context: context, boundingBox: boundingBox, color: color)
    }

    override class var supportsSecureCoding: Bool {
        true
    }
}
