//
//  PDFReaderLayout.swift
//  Zotero
//
//  Created by Michal Rentka on 11/11/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct PDFReaderLayout {
    static let sidebarWidth: CGFloat = createSidebarWidth()
    static let separatorWidth: CGFloat = 1 / UIScreen.main.scale
    static let areaLineWidth: CGFloat = 2
    static let noteSize: CGSize = CGSize(width: 32, height: 32)

    private static func createSidebarWidth() -> CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 320
        }
        return UIScreen.main.bounds.width
    }
}
