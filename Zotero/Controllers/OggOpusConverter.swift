//
//  OggOpusConverter.swift
//  Zotero
//
//  Created by Michal Rentka on 23.02.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import SwiftOGG

enum OggOpusConverter {
    enum Error: Swift.Error {
        case invalidOpusHeader
    }

    struct OpusInfo {
        let channelCount: Int
        let sampleRate: Int
    }

    /// OGG file magic bytes ("OggS")
    private static let oggMagicBytes: [UInt8] = [0x4F, 0x67, 0x67, 0x53]
    /// Opus identification header magic bytes ("OpusHead")
    private static let opusHeadMagic: [UInt8] = [0x4F, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64]

    /// Checks if the given data is in OGG format by checking for the "OggS" magic bytes.
    static func isOggFormat(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data.prefix(4).elementsEqual(oggMagicBytes)
    }

    /// Parses Opus audio parameters from OGG/Opus data.
    /// Returns channel count and original sample rate from the Opus identification header.
    static func parseOpusInfo(_ data: Data) -> OpusInfo? {
        // Find "OpusHead" in the data (it's in the first OGG page, after the OGG header)
        // OGG page header is at least 27 bytes, then segment table, then payload
        guard data.count >= 47 else { return nil }

        // Search for OpusHead magic in first 100 bytes
        let searchRange = min(100, data.count - 19)
        for i in 0..<searchRange {
            let slice = data[i..<min(i + 8, data.count)]
            if slice.elementsEqual(opusHeadMagic) {
                // Found OpusHead at position i
                // Opus header layout:
                // 0-7: "OpusHead"
                // 8: version
                // 9: channel count
                // 10-11: pre-skip (little-endian)
                // 12-15: input sample rate (little-endian uint32)
                let headerStart = i
                guard data.count >= headerStart + 16 else { return nil }

                let channelCount = Int(data[headerStart + 9])
                let sampleRate = Int(data[headerStart + 12]) |
                                 (Int(data[headerStart + 13]) << 8) |
                                 (Int(data[headerStart + 14]) << 16) |
                                 (Int(data[headerStart + 15]) << 24)

                return OpusInfo(channelCount: channelCount, sampleRate: sampleRate)
            }
        }
        return nil
    }

    /// Valid Opus sample rates - decoder picks closest one to input
    private static let validOpusSampleRates: [UInt32] = [8000, 12000, 16000, 24000, 48000]

    /// Returns the closest valid Opus sample rate to the given input rate.
    /// This matches OGGDecoder's internal logic.
    private static func closestValidOpusSampleRate(to inputRate: Int) -> UInt32 {
        let input = UInt32(inputRate)
        return validOpusSampleRates.min(by: { abs(Int32($0) - Int32(input)) < abs(Int32($1) - Int32(input)) }) ?? 48000
    }

    /// Converts OGG/Opus audio data to WAV format that AVAudioPlayer can play.
    /// If the data is not in OGG format, returns the original data unchanged.
    static func convertToPlayableFormat(_ data: Data) throws -> Data {
        guard isOggFormat(data) else {
            return data
        }
        return try convertOggOpusToWAV(data)
    }

    /// Converts OGG/Opus data to WAV format (in memory, no temp files).
    private static func convertOggOpusToWAV(_ oggData: Data) throws -> Data {
        // Parse audio parameters from Opus header
        guard let opusInfo = parseOpusInfo(oggData) else {
            throw Error.invalidOpusHeader
        }

        // Decode OGG/Opus to PCM (Float32 interleaved)
        let decoder = try OGGDecoder(audioData: oggData)
        let pcmFloatData = decoder.pcmData

        // Convert Float32 PCM to Int16 PCM for WAV
        let floatCount = pcmFloatData.count / MemoryLayout<Float>.size
        var int16Data = Data(capacity: floatCount * MemoryLayout<Int16>.size)

        pcmFloatData.withUnsafeBytes { floatBuffer in
            let floats = floatBuffer.bindMemory(to: Float.self)
            for i in 0..<floatCount {
                // Clamp and convert float [-1.0, 1.0] to Int16
                let clamped = max(-1.0, min(1.0, floats[i]))
                var int16Value = Int16(clamped * Float(Int16.max))
                withUnsafeBytes(of: &int16Value) { int16Data.append(contentsOf: $0) }
            }
        }

        // Build WAV file in memory
        // OGGDecoder outputs at a sample rate based on input - use closest valid Opus rate
        let sampleRate: UInt32 = closestValidOpusSampleRate(to: opusInfo.sampleRate)
        let numChannels: UInt16 = UInt16(opusInfo.channelCount)
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)
        let dataSize: UInt32 = UInt32(int16Data.count)
        let fileSize: UInt32 = 36 + dataSize

        var wavData = Data()

        // RIFF header
        wavData.append(contentsOf: "RIFF".utf8)
        wavData.append(littleEndian: fileSize)
        wavData.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wavData.append(contentsOf: "fmt ".utf8)
        wavData.append(littleEndian: UInt32(16)) // chunk size
        wavData.append(littleEndian: UInt16(1))  // audio format (PCM)
        wavData.append(littleEndian: numChannels)
        wavData.append(littleEndian: sampleRate)
        wavData.append(littleEndian: byteRate)
        wavData.append(littleEndian: blockAlign)
        wavData.append(littleEndian: bitsPerSample)

        // data chunk
        wavData.append(contentsOf: "data".utf8)
        wavData.append(littleEndian: dataSize)
        wavData.append(int16Data)

        return wavData
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        var leValue = value.littleEndian
        Swift.withUnsafeBytes(of: &leValue) { append(contentsOf: $0) }
    }
}
