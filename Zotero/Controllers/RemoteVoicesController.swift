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
            .map({ Self.normalizeAudio($0) })
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
            .map({ Self.normalizeAudio($0) })
    }

    /// Peak-normalizes audio data to a target dB level so all voices play at consistent volume.
    /// Works directly on WAV PCM data in memory. Non-WAV data is returned unchanged.
    private static func normalizeAudio(_ data: Data, targetDB: Float = -1.0) -> Data {
        // Verify RIFF/WAVE header
        guard data.count > 44,
              data[0..<4].elementsEqual("RIFF".utf8),
              data[8..<12].elementsEqual("WAVE".utf8)
        else {
            return data
        }

        // Find "data" chunk
        var offset = 12
        var dataChunkOffset = -1
        var dataChunkSize = 0
        while offset + 8 <= data.count {
            let chunkID = String(bytes: data[offset..<(offset + 4)], encoding: .ascii)
            let chunkSize = Int(data[offset + 4]) | (Int(data[offset + 5]) << 8) | (Int(data[offset + 6]) << 16) | (Int(data[offset + 7]) << 24)
            if chunkID == "data" {
                dataChunkOffset = offset + 8
                dataChunkSize = chunkSize
                break
            }
            offset += 8 + chunkSize
        }

        guard dataChunkOffset >= 0, dataChunkOffset + dataChunkSize <= data.count else { return data }

        // Read bitsPerSample from fmt chunk (byte 34-35 in standard WAV)
        let bitsPerSample = Int(data[34]) | (Int(data[35]) << 8)
        guard bitsPerSample == 16 else { return data }

        let sampleCount = dataChunkSize / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return data }

        // Find peak amplitude
        var peak: Float = 0.0
        data.withUnsafeBytes { rawBuffer in
            let base = rawBuffer.baseAddress!.advanced(by: dataChunkOffset).assumingMemoryBound(to: Int16.self)
            for i in 0..<sampleCount {
                let sample = Float(Int16(littleEndian: base[i]))
                let absolute = abs(sample)
                if absolute > peak {
                    peak = absolute
                }
            }
        }

        guard peak > 0 else { return data }

        let targetPeak = pow(10.0, targetDB / 20.0) * Float(Int16.max)
        let gain = targetPeak / peak

        // Apply gain to samples
        var normalized = data
        normalized.withUnsafeMutableBytes { rawBuffer in
            let base = rawBuffer.baseAddress!.advanced(by: dataChunkOffset).assumingMemoryBound(to: Int16.self)
            for i in 0..<sampleCount {
                let sample = Float(Int16(littleEndian: base[i])) * gain
                let clamped = max(Float(Int16.min), min(Float(Int16.max), sample))
                base[i] = Int16(clamped).littleEndian
            }
        }

        return normalized
    }
    
    func downloadSound(forText text: String, voiceId: String, language: String) -> Single<Data> {
        return apiClient
            .send(request: ReadAloudAudioRequest(voiceId: voiceId, text: text, language: language))
            .flatMap({ (data, _) in
                if let data = data.audioData {
                    return .just(data)
                } else {
                    return .error(Error.noData)
                }
            })
    }
}
