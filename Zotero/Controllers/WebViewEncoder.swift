//
//  WebViewEncoder.swift
//  Zotero
//
//  Created by Michal Rentka on 15.11.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct WebViewEncoder {
    static func optionalToJs(_ value: String?) -> String {
        return value.flatMap({ "'" + $0 + "'" }) ?? "null"
    }

    /// Encodes data which need to be sent to `webView`. All data that is passed to JS is Base64 encoded so that it can be sent as a simple `String`.
    static func encodeForJavascript(_ data: Data?) -> String {
        return data.flatMap({ "'" + $0.base64EncodedString(options: .endLineWithLineFeed) + "'" }) ?? "null"
    }

    /// Encodes as JSON payload so that it can be sent to `webView`.
    static func encodeAsJSONForJavascript(_ payload: Any) -> String {
        let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
        return self.encodeForJavascript(data)
    }
}
