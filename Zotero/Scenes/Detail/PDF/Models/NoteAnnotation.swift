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
        return CGSize(width: 20, height: 20)
    }

    override func drawImage(in context: CGContext, boundingBox: CGRect, options: RenderOptions?) {
        let outlineImage = Asset.Images.Annotations.annotationNote.image
        let colorizedImage = Asset.Images.Annotations.annotationNoteColor.image

        guard let colorizedCgImage = colorizedImage.cgImage, let outlineCgImage = outlineImage.cgImage, let color = self.color else { return }

        context.clip(to: boundingBox, mask: colorizedCgImage)
        color.setFill()
        context.fill(boundingBox)

        context.resetClip()
        context.draw(outlineCgImage, in: boundingBox)
    }
}
