//
//  ReadAloudSampleResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 29.01.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

struct ReadAloudAudioResponse: Decodable {
    let audio: String

    var audioData: Data? {
        guard let base64Encoded = audio.data(using: .utf8) else { return nil }
        return Data(base64Encoded: base64Encoded)
    }
}
