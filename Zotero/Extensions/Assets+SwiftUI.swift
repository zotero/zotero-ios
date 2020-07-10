//
//  Assets+SwiftUI.swift
//  Zotero
//
//  Created by Michal Rentka on 10/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

extension ColorAsset {
    var swiftUiColor: SwiftUI.Color {
        return SwiftUI.Color(self.color)
    }
}
