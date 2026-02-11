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

    func loadVoices() -> Single<([RemoteVoice], Int)> {
        return apiClient.send(request: VoicesRequest()).flatMap({ (voices: [RemoteVoice], response: HTTPURLResponse) in
            let remaining = (response.allHeaderFields["zotero-tts-credits-remaining"] as? String).flatMap({ Int($0) }) ?? 0
            return .just((voices, remaining))
        })
    }
    
    func downloadSample(voiceId: String, language: String) -> Single<Data> {
        return apiClient
            .send(request: ReadAloudSampleRequest(voiceId: voiceId, language: language))
            .flatMap({ (data, _) in
                if let data = data.audioData {
                    return .just(data)
                } else {
                    return .error(Error.noData)
                }
            })
    }
    
    func downloadSound(forText text: String, voiceId: String, language: String) -> Single<(Data, Int)> {
        return apiClient
            .send(request: ReadAloudAudioRequest(voiceId: voiceId, text: text, language: "en-US"))
            .flatMap({ (data, response) in
                if let data = data.audioData {
                    let remaining = (response.allHeaderFields["zotero-tts-credits-remaining"] as? String).flatMap({ Int($0) }) ?? 0
                    return .just((data, remaining))
                } else {
                    return .error(Error.noData)
                }
            })
    }
}
