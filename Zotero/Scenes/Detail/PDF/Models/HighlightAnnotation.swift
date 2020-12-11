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
    private static let noteIconSize: CGSize = CGSize(width: 12, height: 12)

    override var noteIconPoint: CGPoint {
        var point = self.boundingBox.origin
        point.y += self.boundingBox.height - (HighlightAnnotation.noteIconSize.height / 2)
        point.x -= 10
        return point
    }

    override var shouldDrawNoteIconIfNeeded: Bool {
        return false
    }

    override func draw(context: CGContext, options: RenderOptions?) {
        super.draw(context: context, options: options)

        guard let color = self.color,
              let colorizedCgImage = Asset.Images.Annotations.annotationNoteColor.image.cgImage,
              let outlineCgImage = Asset.Images.Annotations.annotationNote.image.cgImage else { return }

        let origin = self.noteIconPoint

        let colorizedRect = CGRect(origin: origin, size: HighlightAnnotation.noteIconSize)

        context.clip(to: colorizedRect, mask: colorizedCgImage)
        color.setFill()
        context.fill(colorizedRect)

        let outlineRect = CGRect(origin: origin, size: HighlightAnnotation.noteIconSize)
        context.draw(outlineCgImage, in: outlineRect)
    }
}
