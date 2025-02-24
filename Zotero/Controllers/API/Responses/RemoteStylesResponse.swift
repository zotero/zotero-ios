//
//  RemoteStylesResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 20.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct RemoteStylesResponse: Decodable {
    let styles: [RemoteStyle]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()

        var styles: [RemoteStyle] = []

        while !container.isAtEnd {
            do {
                let style = try container.decode(RemoteStyle.self)
                styles.append(style)
            } catch let error {
                DDLogWarn("CitationStylesResponse: can't parse style - \(error)")
                _ = try container.decode(EmptyDecodable.self)
            }
        }

        self.styles = styles
    }
}
