//
//  SDTPack.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 12/6/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import Compression

final class SDTPack {
    enum Error: Swift.Error {
        case invalidMagic
        case unsupportedPackVersion(UInt8)
        case invalidHeader
        case invalidIndex
        case invalidLayout
        case invalidRange
        case invalidContentChunk
        case inflateFailed
        case invalidJSON
    }

    private struct Header {
        let packVersion: UInt8
        let schemaVersion: String
        let indexLength: Int
    }

    private struct Index {
        let metadataLength: Int
        let catalogLength: Int
        let chunkByteOffsets: [Int]
        let chunkBlockStarts: [Int]
    }

    private static let magic = Data([0x89, 0x53, 0x44, 0x54, 0x0d, 0x0a, 0x1a, 0x0a])
    private static let headerSize = 16
    private static let indexFixedSize = 8
    private static let u32Size = 4
    private static let supportedPackVersion: UInt8 = 1

    private let data: Data
    private let header: Header
    private let index: Index
    private lazy var metadataResult: Result<[String: Any], Swift.Error> = {
        return Result { try readDictionaryJSON(range: metadataRange()) }

        func metadataRange() -> Range<Int> {
            let start = Self.headerSize + header.indexLength
            return start..<(start + index.metadataLength)
        }
    }()
    private lazy var catalogResult: Result<[String: Any], Swift.Error> = {
        return Result { try readDictionaryJSON(range: catalogRange()) }

        func catalogRange() -> Range<Int> {
            let start = Self.headerSize + header.indexLength + index.metadataLength
            return start..<(start + index.catalogLength)
        }
    }()

    init(data: Data) throws {
        guard data.count >= Self.headerSize else { throw Error.invalidHeader }
        guard Data(data.prefix(Self.magic.count)) == Self.magic else { throw Error.invalidMagic }

        let packVersion = data[8]
        guard packVersion == Self.supportedPackVersion else {
            throw Error.unsupportedPackVersion(packVersion)
        }

        let indexLength = try Self.readU32LE(in: data, at: 12)
        guard indexLength >= Self.indexFixedSize + Self.u32Size * 2,
              (indexLength - Self.indexFixedSize).isMultiple(of: Self.u32Size * 2),
              Self.headerSize + indexLength <= data.count else {
            throw Error.invalidHeader
        }

        let header = Header(
            packVersion: packVersion,
            schemaVersion: "\(data[9]).\(data[10]).\(data[11])",
            indexLength: indexLength
        )
        let index = try Self.readIndex(in: data, header: header)
        try Self.validateLayout(data: data, header: header, index: index)

        self.data = data
        self.header = header
        self.index = index
    }

    func materialize() throws -> [String: Any] {
        let metadata = try getMetadata()
        let catalog = try getCatalog()
        var content: [Any] = []

        for chunkIndex in 0..<(index.chunkByteOffsets.count - 1) {
            let chunk = try inflatedContentChunk(at: chunkIndex)
            let blockCount = index.chunkBlockStarts[chunkIndex + 1] - index.chunkBlockStarts[chunkIndex]
            for localBlockIndex in 0..<blockCount {
                let blockData = try blockData(in: chunk, blockCount: blockCount, localBlockIndex: localBlockIndex)
                content.append(try createBlock(from: blockData))
            }
        }

        return [
            "schemaVersion": header.schemaVersion,
            "metadata": metadata,
            "catalog": catalog,
            "content": content
        ]
    }

    func getMetadata() throws -> [String: Any] {
        return try metadataResult.get()
    }

    func getCatalog() throws -> [String: Any] {
        return try catalogResult.get()
    }

    func getTopLevelBlockCount() -> Int {
        return index.chunkBlockStarts.last ?? 0
    }

    func getBlock(ref: [Int]) throws -> [String: Any]? {
        guard let blockIndex = ref.first else { return nil }
        guard let block = try topLevelBlock(at: blockIndex) else { return nil }
        var node: Any = block

        for index in ref.dropFirst() {
            guard index >= 0,
                  let dictionary = node as? [String: Any],
                  let content = dictionary["content"] as? [Any],
                  index < content.count else {
                return nil
            }
            node = content[index]
            guard node is [String: Any] else { return nil }
        }

        return node as? [String: Any]

        func topLevelBlock(at blockIndex: Int) throws -> [String: Any]? {
            guard let resolvedChunkIndex = chunkIndex(containingBlock: blockIndex) else { return nil }
            let chunk = try inflatedContentChunk(at: resolvedChunkIndex)
            let firstBlock = index.chunkBlockStarts[resolvedChunkIndex]
            let blockCount = index.chunkBlockStarts[resolvedChunkIndex + 1] - firstBlock
            let localBlockIndex = blockIndex - firstBlock
            let blockData = try blockData(in: chunk, blockCount: blockCount, localBlockIndex: localBlockIndex)
            return try createBlock(from: blockData)
        }
    }

    func getBlocks(startBlock: Int, endBlock: Int) throws -> [[String: Any]] {
        guard startBlock <= endBlock else { return [] }
        let totalTopLevelBlocks = getTopLevelBlockCount()
        let startBlock = max(0, startBlock)
        let endBlock = min(totalTopLevelBlocks - 1, endBlock)
        guard startBlock <= endBlock else { return [] }
        guard let chunkStart = chunkIndex(containingBlock: startBlock),
              let chunkEnd = chunkIndex(containingBlock: endBlock) else {
            return []
        }

        var blocks: [[String: Any]] = []
        for chunkIndex in chunkStart...chunkEnd {
            let chunk = try inflatedContentChunk(at: chunkIndex)
            let firstBlock = index.chunkBlockStarts[chunkIndex]
            let blockCount = index.chunkBlockStarts[chunkIndex + 1] - firstBlock
            let localStart = max(startBlock - firstBlock, 0)
            let localEnd = min(endBlock - firstBlock, blockCount - 1)
            guard localStart <= localEnd else { continue }

            for localBlockIndex in localStart...localEnd {
                blocks.append(try createLocalBlock(in: chunk, blockCount: blockCount, localBlockIndex: localBlockIndex))
            }
        }
        return blocks

        func createLocalBlock(in chunk: Data, blockCount: Int, localBlockIndex: Int) throws -> [String: Any] {
            let blockData = try blockData(in: chunk, blockCount: blockCount, localBlockIndex: localBlockIndex)
            return try createBlock(from: blockData)
        }
    }

    func getPageBlocks(pageIndex: Int) throws -> [[String: Any]] {
        guard pageIndex >= 0 else { return [] }
        let catalog = try getCatalog()
        guard let pages = catalog["pages"] as? [[String: Any]], pageIndex < pages.count else {
            return []
        }
        guard let span = contentRangeBlockSpan(pages[pageIndex]["contentRange"]),
              span.startIndex < span.endIndexExclusive else {
            return []
        }
        return try getBlocks(startBlock: span.startIndex, endBlock: span.endIndexExclusive - 1)

        func contentRangeBlockSpan(_ value: Any?) -> (startIndex: Int, endIndexExclusive: Int)? {
            guard let range = value as? [Any],
                  range.count == 2,
                  let start = contentBoundary(range[0]),
                  let end = contentBoundary(range[1]),
                  let startIndex = boundaryTopLevelIndex(start) else {
                return nil
            }
            if start == end {
                return (startIndex, startIndex)
            }
            guard let endIndexExclusive = boundaryEndIndexExclusive(end) else { return nil }
            return (startIndex, max(startIndex, endIndexExclusive))

            func contentBoundary(_ value: Any?) -> [Int]? {
                guard let values = value as? [Any], !values.isEmpty else { return nil }
                var boundary: [Int] = []
                for value in values {
                    let intValue: Int?
                    if let value = value as? Int {
                        intValue = value
                    } else if let value = value as? NSNumber {
                        intValue = value.intValue
                    } else {
                        intValue = nil
                    }
                    guard let intValue, intValue >= 0 else { return nil }
                    boundary.append(intValue)
                }
                return boundary
            }

            func boundaryTopLevelIndex(_ boundary: [Int]) -> Int? {
                guard let index = boundary.first, index <= getTopLevelBlockCount() else { return nil }
                return index
            }

            func boundaryEndIndexExclusive(_ boundary: [Int]) -> Int? {
                guard let index = boundaryTopLevelIndex(boundary) else { return nil }
                let topLevelBlockCount = getTopLevelBlockCount()
                if index == topLevelBlockCount {
                    return topLevelBlockCount
                }
                return boundary.count == 1 ? index : index + 1
            }
        }
    }

    private func readDictionaryJSON(range: Range<Int>) throws -> [String: Any] {
        guard let dictionary = try readJSON(range: range) as? [String: Any] else {
            throw Error.invalidJSON
        }
        return dictionary

        func readJSON(range: Range<Int>) throws -> Any {
            let inflated = try Self.inflate(try dataSlice(range))
            do {
                return try JSONSerialization.jsonObject(with: inflated, options: .allowFragments)
            } catch {
                throw Error.invalidJSON
            }
        }
    }

    private func inflatedContentChunk(at chunkIndex: Int) throws -> Data {
        let start = contentStart() + index.chunkByteOffsets[chunkIndex]
        let end = contentStart() + index.chunkByteOffsets[chunkIndex + 1]
        return try Self.inflate(try dataSlice(start..<end))

        func contentStart() -> Int {
            return Self.headerSize + header.indexLength + index.metadataLength + index.catalogLength
        }
    }

    private func createBlock(from data: Data) throws -> [String: Any] {
        guard let block = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any] else {
            throw Error.invalidJSON
        }
        return block
    }

    private func chunkIndex(containingBlock blockIndex: Int) -> Int? {
        guard blockIndex >= 0 else { return nil }
        for chunkIndex in 0..<(index.chunkBlockStarts.count - 1) {
            if blockIndex >= index.chunkBlockStarts[chunkIndex] && blockIndex < index.chunkBlockStarts[chunkIndex + 1] {
                return chunkIndex
            }
        }
        return nil
    }

    private func blockData(in chunk: Data, blockCount: Int, localBlockIndex: Int) throws -> Data {
        guard blockCount >= 0, localBlockIndex >= 0, localBlockIndex < blockCount else {
            throw Error.invalidContentChunk
        }
        let headerByteLength = blockCount * Self.u32Size
        guard chunk.count >= headerByteLength else { throw Error.invalidContentChunk }

        let start = try Self.readU32LE(in: chunk, at: localBlockIndex * Self.u32Size)
        let end = localBlockIndex + 1 < blockCount
            ? try Self.readU32LE(in: chunk, at: (localBlockIndex + 1) * Self.u32Size)
            : chunk.count - headerByteLength
        guard start <= end, headerByteLength + end <= chunk.count else {
            throw Error.invalidContentChunk
        }
        return try Self.slice(chunk, range: (headerByteLength + start)..<(headerByteLength + end))
    }

    private func dataSlice(_ range: Range<Int>) throws -> Data {
        return try Self.slice(data, range: range)
    }

    private static func readIndex(in data: Data, header: Header) throws -> Index {
        let indexStart = headerSize
        let metadataLength = try readU32LE(in: data, at: indexStart)
        let catalogLength = try readU32LE(in: data, at: indexStart + u32Size)
        let entryCount = (header.indexLength - indexFixedSize) / (u32Size * 2)
        var chunkByteOffsets: [Int] = []
        var chunkBlockStarts: [Int] = []

        for index in 0..<entryCount {
            chunkByteOffsets.append(try readU32LE(in: data, at: indexStart + indexFixedSize + index * u32Size))
        }
        for index in 0..<entryCount {
            chunkBlockStarts.append(try readU32LE(in: data, at: indexStart + indexFixedSize + entryCount * u32Size + index * u32Size))
        }

        guard metadataLength > 0,
              catalogLength > 0,
              !chunkByteOffsets.isEmpty,
              chunkByteOffsets.count == chunkBlockStarts.count,
              chunkByteOffsets.first == 0,
              chunkBlockStarts.first == 0 else {
            throw Error.invalidIndex
        }
        if chunkByteOffsets.count > 1 {
            try assertStrictlyIncreasing(chunkByteOffsets)
            try assertStrictlyIncreasing(chunkBlockStarts)
        }
        return Index(metadataLength: metadataLength, catalogLength: catalogLength, chunkByteOffsets: chunkByteOffsets, chunkBlockStarts: chunkBlockStarts)

        func assertStrictlyIncreasing(_ values: [Int]) throws {
            for index in 1..<values.count where values[index] <= values[index - 1] {
                throw Error.invalidIndex
            }
        }
    }

    private static func validateLayout(data: Data, header: Header, index: Index) throws {
        guard let contentLength = index.chunkByteOffsets.last else { throw Error.invalidIndex }
        let contentEnd = headerSize + header.indexLength + index.metadataLength + index.catalogLength + contentLength
        guard contentEnd == data.count else { throw Error.invalidLayout }
    }

    private static func readU32LE(in data: Data, at offset: Int) throws -> Int {
        guard offset >= 0, offset + u32Size <= data.count else { throw Error.invalidRange }
        return Int(data[offset])
            + Int(data[offset + 1]) * 0x100
            + Int(data[offset + 2]) * 0x10000
            + Int(data[offset + 3]) * 0x1000000
    }

    private static func slice(_ data: Data, range: Range<Int>) throws -> Data {
        guard range.lowerBound >= 0, range.upperBound <= data.count, range.lowerBound <= range.upperBound else {
            throw Error.invalidRange
        }
        return data.subdata(in: range)
    }

    private static func inflate(_ data: Data) throws -> Data {
        var capacity = max(data.count * 4, 64 * 1024)
        let maximumCapacity = 512 * 1024 * 1024
        while capacity <= maximumCapacity {
            let result = data.withUnsafeBytes { inputBuffer -> Data? in
                guard let input = inputBuffer.bindMemory(to: UInt8.self).baseAddress else { return Data() }
                var output = [UInt8](repeating: 0, count: capacity)
                let count = output.withUnsafeMutableBufferPointer { outputBuffer in
                    compression_decode_buffer(outputBuffer.baseAddress!, capacity, input, data.count, nil, COMPRESSION_ZLIB)
                }
                guard count > 0 else { return nil }
                guard count < capacity else { return Data() }
                return Data(output.prefix(count))
            }
            if let result {
                if result.isEmpty {
                    capacity *= 2
                    continue
                }
                return result
            }
            throw Error.inflateFailed
        }
        throw Error.inflateFailed
    }
}
