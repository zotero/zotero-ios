//
//  AnnotationManager.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 25/6/24.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import PSPDFKit

class AnnotationManager: PSPDFKit.AnnotationManager {
    override func annotationViewClass(for annotation: Annotation) -> AnyClass? {
        if annotation is SquareAnnotation {
            // Use a custom annotation view subclass for square annotations.
            return SquareAnnotationView.self
        }
        return super.annotationViewClass(for: annotation)
    }
}
