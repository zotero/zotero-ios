//
//  VoicesResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 27.02.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import OrderedCollections

import CocoaLumberjackSwift

struct VoicesResponse {
    struct Data {
        struct Locale {
            let `default`: [String]
            let other: [String]
        }

        let creditsPerMinute: Int
        let sentenceDelay: Int
        let sentenceGranularity: RemoteVoice.Granularity
        let voices: [String: String]
        let locales: OrderedDictionary<String, Locale>

        init(response: [String: Any]) throws {
            let rawGranularity: String = try response.apiGet(key: "sentenceGranularity", caller: Self.self)
            guard let granularity = RemoteVoice.Granularity(rawValue: rawGranularity) else {
                throw Parsing.Error.incompatibleValue("sentenceGranularity=\(rawGranularity)")
            }
            creditsPerMinute = try response.apiGet(key: "creditsPerMinute", caller: Self.self)
            sentenceGranularity = granularity
            sentenceDelay = try response.apiGet(key: "sentenceDelay", caller: Self.self)

            guard let voicesData = response["voices"] as? [String: Any] else {
                throw Parsing.Error.missingKey("voices")
            }
            guard let localesData = response["locales"] as? [String: Any] else {
                throw Parsing.Error.missingKey("locales")
            }

            var voices: [String: String] = [:]
            for (key, value) in voicesData {
                guard let data = value as? [String: String], let label = data["label"] else {
                    DDLogError("VoicesResponse: voice doesn't contain label - \(key); \(value)")
                    throw Parsing.Error.missingKey("label")
                }
                voices[key] = label
            }
            self.voices = voices

            var locales: OrderedDictionary<String, Locale> = [:]
            for (key, value) in localesData {
                guard let data = value as? [String: [String]] else {
                    DDLogError("VoicesResponse: incompatible locales - \(key); \(value)")
                    throw Parsing.Error.notDictionary
                }
                var defaultLocales: [String] = []
                var otherLocales: [String] = []
                if let locales = data["default"] {
                    defaultLocales = locales
                }
                if let locales = data["other"] {
                    otherLocales = locales
                }
                locales[key] = Locale(default: defaultLocales, other: otherLocales)
            }
            self.locales = locales
        }

        func firstVoice(for tier: RemoteVoice.Tier) -> RemoteVoice? {
            guard let locale = locales.keys.first, let localeData = locales[locale] else { return nil }
            let voiceId: String
            if !localeData.default.isEmpty {
                voiceId = localeData.default[0]
            } else if !localeData.other.isEmpty {
                voiceId = localeData.other[0]
            } else {
                return nil
            }
            let label = voices[voiceId] ?? ""
            return RemoteVoice(id: voiceId, label: label, creditsPerMinute: creditsPerMinute, granularity: sentenceGranularity, sentenceDelay: sentenceDelay, tier: tier)
        }
    }

    let tiers: [RemoteVoice.Tier: [Data]]

    init(response: [String: Any]) throws {
        var tiers: [RemoteVoice.Tier: [Data]] = [:]
        if let data = response["premium"] as? [[String: Any]] {
            tiers[.premium] = try data.map({ try Data(response: $0) })
        }
        if let data = response["standard"] as? [[String: Any]] {
            tiers[.standard] = try data.map({ try Data(response: $0) })
        }
        self.tiers = tiers
    }

    func firstVoice(for tier: RemoteVoice.Tier) -> RemoteVoice? {
        guard let tierData = tiers[tier], !tierData.isEmpty else { return nil }
        return tierData.compactMap({ $0.firstVoice(for: tier) }).first
    }
}
