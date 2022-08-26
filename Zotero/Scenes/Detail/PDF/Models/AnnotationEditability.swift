//
//  AnnotationEditability.swift
//  Zotero
//
//  Created by Michal Rentka on 26.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

/// Editability of annotations
/// - notEditable: Annotation is not editable at all.
/// - deletable: Annotation can only be deleted.
/// - editable: Annotation can be fully edited.
enum AnnotationEditability: Equatable, Hashable {
    case notEditable
    case deletable
    case editable
}
