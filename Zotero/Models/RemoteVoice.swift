//
//  RemoteVoice.swift
//  Zotero
//
//  Created by Michal Rentka on 14.01.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

struct RemoteVoice: Decodable, Equatable {
    let id: String
    let label: String
    let creditsPerSecond: Int
    let segmentGranularity: String
    
    static func ==(lhs: RemoteVoice, rhs: RemoteVoice) -> Bool {
        return lhs.id == rhs.id
    }
}
