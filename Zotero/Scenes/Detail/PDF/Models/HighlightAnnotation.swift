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
        point.x -= HighlightAnnotation.noteIconSize.width
        return point
    }

    override var shouldDrawNoteIconIfNeeded: Bool {
        return false
    }

    override func draw(context: CGContext, options: RenderOptions?) {
        super.draw(context: context, options: options)

        guard let color = self.color,
              let colorizedCgImage = Asset.Images.Annotations.commentColor.image.cgImage,
              let outlineCgImage = Asset.Images.Annotations.comment.image.cgImage else { return }

        let boundingBox = CGRect(origin: self.noteIconPoint, size: HighlightAnnotation.noteIconSize)

        context.clip(to: boundingBox, mask: colorizedCgImage)
        color.setFill()
        context.fill(boundingBox)

        context.resetClip()
        context.draw(outlineCgImage, in: boundingBox)
    }
}
