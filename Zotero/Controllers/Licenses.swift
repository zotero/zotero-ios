//
//  Licenses.swift
//  Zotero
//
//  Created by Michal Rentka on 04/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

final class Licenses {
    static let shared = Licenses()

    let pspdfkitKey: String?

    init() {
        guard let path = Bundle.main.path(forResource: "licenses", ofType: "plist", inDirectory: "licenses"),
              let data = NSDictionary(contentsOfFile: path) else {
            self.pspdfkitKey = nil
            return
        }
        self.pspdfkitKey = data["pspdfkit"] as? String
    }
}
