//
//  LinkMode.swift
//  Zotero
//
//  Created by Michal Rentka on 16/09/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum LinkMode: String {
    case linkedFile = "linked_file"
    case importedFile = "imported_file"
    case linkedUrl = "linked_url"
    case importedUrl = "imported_url"
    case embeddedImage = "embedded_image"
}
