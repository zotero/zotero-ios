//
//  Licenses.swift
//  Zotero
//
//  Created by Michal Rentka on 04/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

class Licenses {
    static let shared = Licenses()

    let pspdfkitKey: String?

    init() {
        guard let path = Bundle.main.path(forResource: "licenses", ofType: "plist"),
              let data = NSDictionary(contentsOfFile: path) else {
            self.pspdfkitKey = nil
            return
        }
        self.pspdfkitKey = data["pspdfkit"] as? String
    }
}
