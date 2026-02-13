//
//  ReadAloudAudioRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 15.01.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

struct ReadAloudAudioRequest: ApiRequest {
    let voiceId: String
    let text: String
    let language: String

    var endpoint: ApiEndpoint {
        return .zotero(path: "tts/speak")
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String: Any]? {
        return ["text": text, "voice": voiceId, "lang": language]
    }

    var headers: [String: String]? {
        return nil
    }
}

struct ReadAloudSampleRequest: ApiRequest {
    let voiceId: String
    let language: String

    var endpoint: ApiEndpoint {
        return .zotero(path: "tts/sample")
    }

    var httpMethod: ApiHttpMethod {
        return .get
    }

    var encoding: ApiParameterEncoding {
        return .url
    }

    var parameters: [String: Any]? {
        return ["voice": voiceId, "lang": language]
    }

    var headers: [String: String]? {
        return nil
    }
}
