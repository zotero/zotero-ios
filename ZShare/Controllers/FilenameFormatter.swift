//
//  FilenameFormatter.swift
//  ZShare
//
//  Created by Michal Rentka on 25.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct FilenameFormatter {
    static func filename(from item: ItemResponse, defaultTitle: String, ext: String, dateParser: DateParser) -> String {
        var filename = ""

        if let creators = self.creators(for: item) {
            filename = creators
        }

        if let year = self.year(for: item, dateParser: dateParser) {
            filename += " - " + year
        }

        let title = item.fields[FieldKeys.Item.Attachment.title] ?? defaultTitle

        if filename.isEmpty {
            return title + "." + ext
        }

        return filename + " - " + title + "." + ext
    }

    private static func creators(for item: ItemResponse) -> String? {
        let creators = item.creators
        switch creators.count {
        case 0:
            return nil
        case 1:
            return creators.first?.summaryName
        case 2:
            return "\(creators.first?.summaryName ?? "") and \(creators.last?.summaryName ?? "")"
        default:
            return "\(creators.first?.summaryName ?? "") et al."
        }
    }

    private static func year(for item: ItemResponse, dateParser: DateParser) -> String? {
        return item.fields[FieldKeys.Item.date].flatMap({ dateParser.parse(string: $0) })
                                               .flatMap({ "\($0.year)" })
    }
}

extension CreatorResponse {
    fileprivate var summaryName: String? {
        if let name = self.name {
            return name
        }
        if let name = self.lastName {
            return name
        }
        return self.firstName
    }
}
