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

    func loadVoices() -> Single<(voices: [RemoteVoice], credits: (standard: Int, premium: Int))> {
        return apiClient.send(request: VoicesRequest()).flatMap({ (voices: [RemoteVoice], response: HTTPURLResponse) in
            let standardCredits = (response.value(forHTTPHeaderField: "zotero-tts-standard-credits-remaining") as NSString?)?.integerValue ?? 0
            let premiumCredits = (response.value(forHTTPHeaderField: "zotero-tts-premium-credits-remaining") as NSString?)?.integerValue ?? 0
            return .just((voices: voices, credits: (standard: standardCredits, premium: premiumCredits)))
        })
    }
    
    func loadCredits() -> Single<(standard: Int, premium: Int)> {
        return apiClient.send(request: CreditsRequest()).flatMap({ response, _ in return .just((standard: response.standardCreditsRemaining, premium: response.premiumCreditsRemaining)) })
    }
    
    func downloadSample(voiceId: String, language: String) -> Single<Data> {
        return apiClient
            .send(request: ReadAloudSampleRequest(voiceId: voiceId, language: language))
            .flatMap({ (data, _) in
                if let data = data {
                    return .just(data)
                } else {
                    return .error(Error.noData)
                }
            })
    }
    
    func downloadSound(forText text: String, voiceId: String, language: String) -> Single<Data> {
        return apiClient
            .send(request: ReadAloudAudioRequest(voiceId: voiceId, text: text, language: "en-US"))
            .flatMap({ (data, _) in
                if let data = data {
                    return .just(data)
                } else {
                    return .error(Error.noData)
                }
            })
    }
}
