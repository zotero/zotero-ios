//
//  MD5+Url.swift
//  Zotero
//
//  Created by Michal Rentka on 22/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import CryptoKit
import Foundation

import CocoaLumberjackSwift

func md5(from url: URL) -> String? {
    let bufferSize = 1024 * 1024

    do {
        // Open file for reading:
        let file = try FileHandle(forReadingFrom: url)
        defer {
            file.closeFile()
        }

        // Create and initialize MD5 hasher:
        var md5 = CryptoKit.Insecure.MD5()
        
        // Read up to `bufferSize` bytes, until EOF is reached, and update MD5 hash:
        while autoreleasepool(invoking: {
            let data = file.readData(ofLength: bufferSize)
            if !data.isEmpty {
                md5.update(data: data)
                return true // Continue
            } else {
                return false // End of file
            }
        }) { }

        // Compute the MD5 digest:
        let digest = md5.finalize()

        return Data(digest).map({ String(format: "%02hhx", $0) }).joined()
    } catch {
        DDLogError("Could not create MD5 from url: \(error)")
        return nil
    }
}

var cachedMD5AndModificationDateByURL: [URL: (String, Date, NSNumber)] = [:]
func cachedMD5(from url: URL, using fileManager: FileManager) -> String? {
    var newModificationDate: Date = .distantPast
    var newSize: NSNumber = .init(value: 0)
    var hasAttributes = false
    if let attributes = try? fileManager.attributesOfItem(atPath: url.path) {
        hasAttributes = true
        if let modificationDate = attributes[.modificationDate] as? Date {
            newModificationDate = modificationDate
        }
        if let size = attributes[.size] as? NSNumber {
            newSize = size
        }
    }
    if let (cachedMd5, cachedModificationDate, cachedSize) = cachedMD5AndModificationDateByURL[url], newModificationDate == cachedModificationDate, newSize == cachedSize {
        return cachedMd5
    }

    if hasAttributes, let cachedMd5 = sidecarCachedMD5(from: url, modificationDate: newModificationDate, size: newSize) {
        cachedMD5AndModificationDateByURL[url] = (cachedMd5, newModificationDate, newSize)
        return cachedMd5
    }

    let md5 = md5(from: url)
    if let md5 {
        cachedMD5AndModificationDateByURL[url] = (md5, newModificationDate, newSize)
        if hasAttributes {
            writeSidecarCachedMD5(md5, for: url, modificationDate: newModificationDate, size: newSize)
        }
    } else {
        cachedMD5AndModificationDateByURL[url] = nil
    }
    return md5
}

private struct SidecarCachedMD5: Codable {
    let filename: String
    let modificationDate: Date
    let size: UInt64
    let md5: String
}

private func sidecarURL(for url: URL) -> URL {
    return url.deletingLastPathComponent().appendingPathComponent(".zotero-source-hash.json")
}

private func sidecarCachedMD5(from url: URL, modificationDate: Date, size: NSNumber) -> String? {
    let sidecarUrl = sidecarURL(for: url)
    guard let data = try? Data(contentsOf: sidecarUrl),
          let cached = try? JSONDecoder().decode(SidecarCachedMD5.self, from: data),
          cached.filename == url.lastPathComponent,
          cached.modificationDate == modificationDate,
          cached.size == size.uint64Value else {
        return nil
    }
    return cached.md5
}

private func writeSidecarCachedMD5(_ md5: String, for url: URL, modificationDate: Date, size: NSNumber) {
    let cached = SidecarCachedMD5(filename: url.lastPathComponent, modificationDate: modificationDate, size: size.uint64Value, md5: md5)
    guard let data = try? JSONEncoder().encode(cached) else { return }
    try? data.write(to: sidecarURL(for: url), options: .atomic)
}
