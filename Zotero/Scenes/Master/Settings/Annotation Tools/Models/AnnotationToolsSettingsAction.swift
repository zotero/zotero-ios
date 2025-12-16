//
//  AnnotationToolsSettingsAction.swift
//  Zotero
//
//  Created by Michal Rentka on 12.12.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum AnnotationToolsSettingsAction {
    case move(IndexSet, Int, AnnotationToolsSettingsState.Section)
    case reset(AnnotationToolsSettingsState.Section)
    case setVisible(Bool, AnnotationTool, AnnotationToolsSettingsState.Section)
    case save
}
