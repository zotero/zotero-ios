//
//  EmptyDecodable.swift
//  Zotero
//
//  Created by Michal Rentka on 11.05.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

/// Decodable used to avoid infinite-loop in case of decoding error when decoding arrays of decodables manually in a while loop.
struct EmptyDecodable: Decodable {}
