//
//  CommentIconDrawingController.swift
//  Zotero
//
//  Created by Michal Rentka on 12.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct CommentIconDrawingController {
    static let iconSize: CGSize = CGSize(width: 12, height: 12)

    static func draw(context: CGContext, boundingBox: CGRect, color: UIColor) {
        guard let colorizedCgImage = Asset.Images.Annotations.commentColor.image.cgImage,
              let outlineCgImage = Asset.Images.Annotations.comment.image.cgImage else { return }

        let size = CommentIconDrawingController.iconSize

        var origin = boundingBox.origin
        origin.y += boundingBox.height - (size.height / 2)
        origin.x -= size.width

        let newBoundingBox = CGRect(origin: origin, size: size)

        context.clip(to: newBoundingBox, mask: colorizedCgImage)
        color.withAlphaComponent(0.5).setFill()
        context.fill(newBoundingBox)

        context.resetClip()
        context.draw(outlineCgImage, in: newBoundingBox)
    }
}
