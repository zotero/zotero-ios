//
//  MD5+Url.swift
//  Zotero
//
//  Created by Michal Rentka on 22/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import CommonCrypto
import Foundation

import CocoaLumberjack

func md5(from url: URL) -> Data? {
    let bufferSize = 1024 * 1024

    do {
        // Open file for reading:
        let file = try FileHandle(forReadingFrom: url)
        defer {
            file.closeFile()
        }

        // Create and initialize MD5 context:
        var context = CC_MD5_CTX()
        CC_MD5_Init(&context)

        // Read up to `bufferSize` bytes, until EOF is reached, and update MD5 context:
        while autoreleasepool(invoking: {
            let data = file.readData(ofLength: bufferSize)
            if data.count > 0 {
                data.withUnsafeBytes {
                    _ = CC_MD5_Update(&context, $0.baseAddress, numericCast(data.count))
                }
                return true // Continue
            } else {
                return false // End of file
            }
        }) { }

        // Compute the MD5 digest:
        var digest: [UInt8] = Array(repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        _ = CC_MD5_Final(&digest, &context)

        return Data(digest)
    } catch {
        DDLogError("Could not create MD5 from url: \(error)")
        return nil
    }
}
