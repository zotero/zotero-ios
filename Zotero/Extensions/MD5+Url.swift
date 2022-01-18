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

    do {
        // Read data from file URL
        let fileData = try Data(contentsOf: url)

        // Compute the MD5 digest:
        let digest = Insecure.MD5.hash(data: fileData)

        return Data(digest).map({ String(format: "%02hhx", $0) }).joined()
    } catch {
        DDLogError("Could not create MD5 from url: \(error)")
        return nil
    }
}
