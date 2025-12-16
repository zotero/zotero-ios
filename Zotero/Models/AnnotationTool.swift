//
//  AnnotationTool.swift
//  Zotero
//
//  Created by Michal Rentka on 14.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

enum AnnotationTool: Hashable, Codable {
    case ink
    case image
    case note
    case highlight
    case eraser
    case underline
    case freeText
    
    var image: UIImage {
        switch self {
        case .highlight:
            return Asset.Images.Annotations.highlightLarge.image
            
        case .note:
            return Asset.Images.Annotations.noteLarge.image
            
        case .image:
            return Asset.Images.Annotations.areaLarge.image
            
        case .ink:
            return Asset.Images.Annotations.inkLarge.image
            
        case .eraser:
            return Asset.Images.Annotations.eraserLarge.image
            
        case .underline:
            return Asset.Images.Annotations.underlineLarge.image
            
        case .freeText:
            return Asset.Images.Annotations.textLarge.image
        }
    }

    var name: String {
        switch self {
        case .eraser:
            return L10n.Pdf.AnnotationToolbar.eraser
            
        case .freeText:
            return L10n.Pdf.AnnotationToolbar.text
            
        case .highlight:
            return L10n.Pdf.AnnotationToolbar.highlight
            
        case .image:
            return L10n.Pdf.AnnotationToolbar.image
            
        case .ink:
            return L10n.Pdf.AnnotationToolbar.ink
            
        case .note:
            return L10n.Pdf.AnnotationToolbar.note
            
        case .underline:
            return L10n.Pdf.AnnotationToolbar.underline
        }
    }
    
    var accessibilityLabel: String {
        switch self {
        case .eraser:
            return L10n.Accessibility.Pdf.eraserAnnotationTool
            
        case .freeText:
            return L10n.Accessibility.Pdf.textAnnotationTool
            
        case .highlight:
            return L10n.Accessibility.Pdf.highlightAnnotationTool
            
        case .image:
            return L10n.Accessibility.Pdf.imageAnnotationTool
            
        case .ink:
            return L10n.Accessibility.Pdf.inkAnnotationTool
            
        case .note:
            return L10n.Accessibility.Pdf.noteAnnotationTool
            
        case .underline:
            return L10n.Accessibility.Pdf.underlineAnnotationTool
        }
    }
}

struct AnnotationToolButton: Codable, Identifiable {
    let type: AnnotationTool
    let isVisible: Bool
    
    var id: AnnotationTool {
        return type
    }
}
