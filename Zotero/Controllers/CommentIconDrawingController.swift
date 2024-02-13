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
        guard let colorizedCgImage = Asset.Images.Annotations.commentColored.image.cgImage, let outlineCgImage = Asset.Images.Annotations.comment.image.cgImage else { return }

        let size = Self.iconSize

        var origin = boundingBox.origin
        origin.y += boundingBox.height - (size.height / 2)
        origin.x -= (size.width / 2)

        let alpha: CGFloat = 0.4
        let newBoundingBox = CGRect(origin: origin, size: size)

        context.clip(to: newBoundingBox, mask: colorizedCgImage)
        color.withAlphaComponent(alpha).setFill()
        context.fill(newBoundingBox)

        context.resetClip()
        context.clip(to: newBoundingBox, mask: outlineCgImage)
        UIColor.black.withAlphaComponent(alpha).setFill()
        context.fill(newBoundingBox)
    }
}
