//
//  KeyGenerator.swift
//  Zotero
//
//  Created by Michal Rentka on 17/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct KeyGenerator {
    static let length = 8
    private static let allowedChars = "23456789ABCDEFGHIJKLMNPQRSTUVWXYZ"

    static var newKey: String {
        return String((0..<length).map({ _ in allowedChars.randomElement()! }))
    }
}
