//
//  RemoteVoice.swift
//  Zotero
//
//  Created by Michal Rentka on 14.01.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

struct RemoteVoice: Equatable {
    enum Granularity: String {
        case sentence
        case paragraph
    }

    enum Tier: String {
        case basic
        case advanced
    }

    let id: String
    let label: String
    let creditsPerSecond: Int
    let granularity: Granularity
    let tier: Tier
    let locales: [String]

    static func ==(lhs: RemoteVoice, rhs: RemoteVoice) -> Bool {
        return lhs.id == rhs.id
    }
}
extension RemoteVoice: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case label
        case creditsPerSecond
        case segmentGranularity
        case locales
        case tier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        creditsPerSecond = try container.decode(Int.self, forKey: .creditsPerSecond)
        locales = try container.decode([String].self, forKey: .locales)

        let granularityString = try container.decode(String.self, forKey: .segmentGranularity)
        guard let granularity = Granularity(rawValue: granularityString) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath + [CodingKeys.segmentGranularity],
                    debugDescription: "Unknown granularity value: \(granularityString)"
                )
            )
        }
        self.granularity = granularity

        let tierString = try container.decode(String.self, forKey: .tier)
        guard let tier = Tier(rawValue: tierString) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath + [CodingKeys.tier],
                    debugDescription: "Unknown tier value: \(tierString)"
                )
            )
        }
        self.tier = tier
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(creditsPerSecond, forKey: .creditsPerSecond)
        try container.encode(granularity.rawValue, forKey: .segmentGranularity)
        try container.encode(locales, forKey: .locales)
        try container.encode(tier.rawValue, forKey: .tier)
    }
}

