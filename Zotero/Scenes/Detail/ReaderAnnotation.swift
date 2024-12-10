//
//  ReaderAnnotation.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 9/12/24.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

protocol ReaderAnnotation {
    var key: String { get }
    var type: AnnotationType { get }
    var pageLabel: String { get }
    var lineWidth: CGFloat? { get }
    var color: String { get }
    var comment: String { get }
    var text: String? { get }
    var fontSize: CGFloat? { get }
    var sortIndex: String { get }
    var dateAdded: Date { get }
    var dateModified: Date { get }
    var tags: [Tag] { get}

    func author(displayName: String, username: String) -> String
    func isAuthor(currentUserId: Int) -> Bool
    func editability(currentUserId: Int, library: Library) -> AnnotationEditability
}
