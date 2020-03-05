//
//  KeysResponseProcessor.swift
//  Zotero
//
//  Created by Michal Rentka on 05/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct KeysResponseProcessor {
    static func redact(response: String) -> String {
        guard let startIndex = response.range(of: "\"key\": \"")?.upperBound,
              let endIndex = response.range(of: "\",",
                                            options: [],
                                            range: startIndex..<response.endIndex,
                                            locale: nil)?.lowerBound else { return response }
        return response.replacingCharacters(in: startIndex..<endIndex, with: "<redacted>")
    }
}
