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

    func loadVoices() -> Single<(voices: [RemoteVoice], credits: (basic: Int, advanced: Int))> {
        return apiClient.send(request: VoicesRequest()).flatMap({ (voices: [RemoteVoice], response: HTTPURLResponse) in
            let basicCredits = (response.value(forHTTPHeaderField: "zotero-tts-basic-credits-remaining") as NSString?)?.integerValue ?? 0
            let advancedCredits = (response.value(forHTTPHeaderField: "zotero-tts-advanced-credits-remaining") as NSString?)?.integerValue ?? 0
            return .just((voices: voices, credits: (basic: basicCredits, advanced: advancedCredits)))
        })
    }
    
    func loadCredits() -> Single<(basic: Int, advanced: Int)> {
        return apiClient.send(request: CreditsRequest()).flatMap({ response, _ in return .just((basic: response.basicCreditsRemaining, advanced: response.advancedCreditsRemaining)) })
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
