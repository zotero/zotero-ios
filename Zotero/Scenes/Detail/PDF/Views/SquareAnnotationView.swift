//
//  SquareAnnotationView.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 25/6/24.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import PSPDFKitUI

class SquareAnnotationView: PSPDFKitUI.HostingAnnotationView {
    private var commentImageView: UIImageView?

    override var annotationImageView: UIImageView? {
        commentImageView?.removeFromSuperview()
        commentImageView = nil
        guard let annotationImageView = super.annotationImageView else {
            return nil
        }
        guard let annotation, let comment = annotation.contents, !comment.isEmpty, !annotation.flags.contains(.hidden) else {
            return annotationImageView
        }
        commentImageView = createCommentImageView(in: annotationImageView)
        return annotationImageView

        func createCommentImageView(in annotationImageView: UIImageView) -> UIImageView {
            let width: CGFloat = 12
            let height: CGFloat = 12
            let alpha: CGFloat = 0.75
            let size = CGSize(width: width, height: height)
            let commentImage = UIGraphicsImageRenderer(size: size).image { context in
                CommentIconDrawingController.draw(context: context.cgContext, origin: .zero, size: size, color: annotation.color ?? .black, alpha: alpha)
            }
            let commentImageView = UIImageView()
            commentImageView.image = commentImage
            commentImageView.contentMode = .scaleAspectFit
            annotationImageView.addSubview(commentImageView)
            commentImageView.translatesAutoresizingMaskIntoConstraints = false
            let widthMultiplier = width / annotation.boundingBox.width
            let heightMultiplier = height / annotation.boundingBox.height
            NSLayoutConstraint.activate([
                commentImageView.widthAnchor.constraint(equalTo: annotationImageView.widthAnchor, multiplier: widthMultiplier),
                commentImageView.heightAnchor.constraint(equalTo: annotationImageView.heightAnchor, multiplier: heightMultiplier),
                commentImageView.centerXAnchor.constraint(equalTo: annotationImageView.leadingAnchor),
                commentImageView.centerYAnchor.constraint(equalTo: annotationImageView.topAnchor)
            ])
            return commentImageView
        }
    }
}
