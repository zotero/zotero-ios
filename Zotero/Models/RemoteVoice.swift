//
//  RemoteVoice.swift
//  Zotero
//
//  Created by Michal Rentka on 14.01.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

struct RemoteVoice: Codable, Equatable {
    enum Granularity {
        case sentence, paragraph
    }
    
    let id: String
    let label: String
    let creditsPerSecond: Int
    let segmentGranularity: String
    let locales: [String]
    
    var granularity: Granularity {
        switch segmentGranularity {
        case "sentence":
            return .sentence
            
        case "paragraph":
            return .paragraph
            
        default:
            return .sentence
        }
    }

    static func ==(lhs: RemoteVoice, rhs: RemoteVoice) -> Bool {
        return lhs.id == rhs.id
    }
}
