//
//  RemoteVoicesController.swift
//  Zotero
//
//  Created by Michal Rentka on 28.01.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

final class RemoteVoicesController {
    enum Error: Swift.Error {
        case noData
    }
    
    private unowned let apiClient: ApiClient

    init(apiClient: ApiClient) {
        self.apiClient = apiClient
    }

    func loadVoices() -> Single<[RemoteVoice]> {
        return apiClient.send(request: VoicesRequest()).flatMap({ (voices: [RemoteVoice], _) in return .just(voices) })
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
    
    func downloadSound(forText text: String, voiceId: String, language: String) -> Single<Data> {
        return apiClient
            .send(request: ReadAloudAudioRequest(voiceId: voiceId, text: text, language: "en-US"))
            .flatMap({ (data, _) in
                if let data = data.audioData {
                    return .just(data)
                } else {
                    return .error(Error.noData)
                }
            })
    }
}
