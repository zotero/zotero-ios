//
//  NoteEditorAction.swift
//  Zotero
//
//  Created by Michal Rentka on 07.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum NoteEditorAction {
    case deleteResource([String: Any])
    case importImages([String: Any])
    case loadResource([String: Any])
    case save
    case saveBeforeClosing
    case setTags([Tag])
    case setText(String)
}
