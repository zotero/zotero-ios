//
//  PSPDFKItAnnotation+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 06.03.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import PSPDFKit

extension PSPDFKit.Annotation.Tool {
    var toolbarTool: AnnotationTool? {
        switch self {
        case .eraser:
            return .eraser

        case .highlight:
            return .highlight

        case .square:
            return .image

        case .ink:
            return .ink

        case .note:
            return .note

        case .freeText:
            return .freeText

        case .underline:
            return .underline

        default:
            return nil
        }
    }
}

extension AnnotationTool {
    var pspdfkitTool: PSPDFKit.Annotation.Tool {
        switch self {
        case .eraser:
            return .eraser

        case .highlight:
            return .highlight

        case .image:
            return .square

        case .ink:
            return .ink

        case .note:
            return .note

        case .freeText:
            return .freeText

        case .underline:
            return .underline
        }
    }
}

extension PSPDFKit.Annotation.Kind {
    var annotationType: AnnotationType? {
        switch self {
        case .note:
            return .note

        case .highlight:
            return .highlight

        case .square:
            return .image

        case .ink:
            return .ink

        case .underline:
            return .underline

        case .freeText:
            return .freeText

        default:
            return nil
        }
    }
}

extension AnnotationType {
    var kind: PSPDFKit.Annotation.Kind {
        switch self {
        case .note:
            return .note

        case .highlight:
            return .highlight

        case .image:
            return .square

        case .ink:
            return .ink

        case .underline:
            return .underline

        case .freeText:
            return .freeText
        }
    }
}
