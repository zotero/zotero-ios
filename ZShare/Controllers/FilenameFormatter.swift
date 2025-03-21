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
        let filename = [
            creators(for: item),
            year(for: item, dateParser: dateParser),
            String((item.fields[KeyBaseKeyPair(key: FieldKeys.Item.Attachment.title, baseKey: nil)] ?? defaultTitle).prefix(100))
        ].compactMap({ $0 }).filter({ !$0.isEmpty }).joined(separator: " - ") + "." + ext

        return validate(filename: filename)
    }

    static func validate(filename: String) -> String {
        // URL encode
        var valid = filename.replacingOccurrences(of: #"[/\\?*:|"<>]"#, with: "", options: .regularExpression, range: nil)
        // Replace newlines and tabs with spaces
        valid = valid.replacingOccurrences(of: #"[\r\n\t]"#, with: " ", options: .regularExpression, range: nil)
        // Replace various thin spaces
        valid = valid.replacingOccurrences(of: #"[\u2000-\u200A]"#, with: " ", options: .regularExpression, range: nil)
        // Replace zero-width spaces
        valid = valid.replacingOccurrences(of: #"[\u200B-\u200E]"#, with: "", options: .regularExpression, range: nil)
        // Don't allow blank or illegal filenames
        if valid.isEmpty || valid == "." || valid == ".." {
            return "_"
        }
        // Don't allow hidden files
        if valid[valid.startIndex] == "." {
            return String(valid[valid.index(valid.startIndex, offsetBy: 1)..<valid.endIndex])
        }
        return valid
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
        return item.fields[KeyBaseKeyPair(key: FieldKeys.Item.date, baseKey: nil)].flatMap({ dateParser.parse(string: $0) })
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
