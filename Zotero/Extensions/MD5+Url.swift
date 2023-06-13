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
