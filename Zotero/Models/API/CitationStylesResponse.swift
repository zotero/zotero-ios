//
//  CitationStylesResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 20.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct CitationStylesResponse: Decodable {
    let styles: [RemoteCitationStyle]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()

        var styles: [RemoteCitationStyle] = []

        while !container.isAtEnd {
            do {
                let style = try container.decode(RemoteCitationStyle.self)
                styles.append(style)
            } catch let error {
                DDLogWarn("CitationStylesResponse: can't parse style - \(error)")
            }
        }

        self.styles = styles
    }
}
