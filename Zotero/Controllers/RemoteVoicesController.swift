//
//  RemoteVoicesController.swift
//  Zotero
//
//  Created by Michal Rentka on 28.01.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

final class RemoteVoicesController {
    enum Error: Swift.Error {
        case noData
    }
    
    private unowned let apiClient: ApiClient

    init(apiClient: ApiClient) {
        self.apiClient = apiClient
    }

    func loadVoices() -> Single<(response: VoicesResponse, credits: (standard: Int, premium: Int))> {
        return apiClient.send(request: VoicesRequest()).flatMap({ (data: Data?, response: HTTPURLResponse) in
            do {
                guard let data else {
                    DDLogError("RemoteVoicesController: missing response data")
                    throw Parsing.Error.missingKey("data")
                }
                guard let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any] else {
                    DDLogError("RemoteVoicesController: response not dictionary")
                    throw Parsing.Error.notDictionary
                }
                let voicesResponse = try VoicesResponse(response: jsonObject)
                let standardCredits = (response.value(forHTTPHeaderField: "zotero-tts-standard-credits-remaining") as NSString?)?.integerValue ?? 0
                let premiumCredits = (response.value(forHTTPHeaderField: "zotero-tts-premium-credits-remaining") as NSString?)?.integerValue ?? 0
                return .just((response: voicesResponse, credits: (standard: standardCredits, premium: premiumCredits)))
            } catch let error {
                return .error(error)
            }
        })
    }
    
    func loadCredits() -> Single<(standard: Int, premium: Int)> {
        return apiClient.send(request: CreditsRequest()).flatMap({ response, _ in return .just((standard: response.standardCreditsRemaining, premium: response.premiumCreditsRemaining)) })
    }
    
    func downloadSample(voiceId: String) -> Single<Data> {
        return apiClient
            .send(request: ReadAloudSampleRequest(voiceId: voiceId))
            .flatMap({ (data, _) in
                if let data = data {
                    return .just(data)
                } else {
                    return .error(Error.noData)
                }
            })
            .map({ try OggOpusConverter.convertToPlayableFormat($0) })
    }
    
    func downloadSound(forText text: String, voiceId: String) -> Single<Data> {
        return apiClient
            .send(request: ReadAloudAudioRequest(voiceId: voiceId, text: text))
            .flatMap({ (data, _) in
                if let data = data {
                    return .just(data)
                } else {
                    return .error(Error.noData)
                }
            })
            .map({ try OggOpusConverter.convertToPlayableFormat($0) })
    }
}
