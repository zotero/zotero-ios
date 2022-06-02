//
//  AnnotationsFilterAction.swift
//  Zotero
//
//  Created by Michal Rentka on 01.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum AnnotationsFilterAction {
    case toggleColor(String)
    case setTags(Set<String>)
    case clear
}
