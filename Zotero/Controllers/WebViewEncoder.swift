//
//  WebViewEncoder.swift
//  Zotero
//
//  Created by Michal Rentka on 15.11.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct WebViewEncoder {
    static func optionalToJs(_ value: String?) -> String {
        return value.flatMap({ "'" + $0 + "'" }) ?? "null"
    }

    /// Encodes data which need to be sent to `webView`. All data that is passed to JS is Base64 encoded so that it can be sent as a simple `String`.
    static func encodeForJavascript(_ data: Data?) -> String {
        return data.flatMap({ "'" + $0.base64EncodedString(options: .endLineWithLineFeed) + "'" }) ?? "null"
    }

    /// Encodes as a JSON literal which is inlined in the called javascript, for the calls which use the value directly
    /// instead of decoding it first. Most calls take a Base64 encoded string instead - see `encodeAsJSONForJavascript`.
    static func encodeAsInlineJSONForJavascript(_ payload: Any) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else {
            DDLogError("WebViewEncoder: payload can't be encoded as JSON - \(payload)")
            return "null"
        }
        return json
    }

    /// Encodes as JSON payload so that it can be sent to `webView`.
    static func encodeAsJSONForJavascript(_ payload: Any) -> String {
        // A payload which holds a value that can't be represented in JSON raises an exception instead of throwing, so
        // `try` can't catch it. Report it as an unencodable payload, the same as any other encoding failure.
        guard JSONSerialization.isValidJSONObject(payload) else {
            DDLogError("WebViewEncoder: payload can't be encoded as JSON - \(payload)")
            return encodeForJavascript(nil)
        }
        let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
        return self.encodeForJavascript(data)
    }
}
