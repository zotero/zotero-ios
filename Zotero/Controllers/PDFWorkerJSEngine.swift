//
//  PDFWorkerJSEngine.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 30/12/25.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import JavaScriptCore
import Security

final class PDFWorkerJSEngine {
    enum EngineError: Swift.Error {
        case missingShim
        case missingWorker
        case scriptReadFailed(URL)
        case evaluationFailed(String)
    }

    private let context: JSContext
    private let queue: DispatchQueue
    private let bundle: Bundle
    private var lastException: String?
    private var bufferFromArrayFunction: JSValue?
    private var uint8ArrayFromArrayFunction: JSValue?
    private var uint8ArrayFromBufferFunction: JSValue?
    private var timeoutId: Int
    private var timeouts: [Int: DispatchWorkItem]
    private var intervals: [Int: DispatchWorkItem]

    var onPostMessage: ((Any?, [Any]) -> Void)?
    var onLog: ((Any) -> Void)?
    var onException: ((String) -> Void)?

    init(bundle: Bundle = .main, queue: DispatchQueue) {
        self.bundle = bundle
        self.queue = queue
        context = JSContext()
        timeoutId = 1
        timeouts = [:]
        intervals = [:]
        installNativeBridges()
        installHelpers()
        context.exceptionHandler = { [weak self] _, exception in
            let message = exception?.toString() ?? "Unknown JS exception"
            self?.lastException = message
            self?.onException?(message)
        }
    }

    func loadWorkerScripts() throws {
        guard let shimURL = bundle.url(forResource: "pdf_worker_shim", withExtension: "js") else {
            throw EngineError.missingShim
        }
        guard let workerURL = bundle.url(forResource: "worker", withExtension: "js", subdirectory: "Bundled/pdf_worker") else {
            throw EngineError.missingWorker
        }
        try evaluateScript(at: shimURL)
        try evaluateScript(at: workerURL)
    }

    func makeObject() -> JSValue {
        return JSValue(newObjectIn: context) ?? JSValue(nullIn: context)
    }

    func makeArrayBuffer(from data: Data) -> JSValue? {
        return bufferFromArrayFunction?.call(withArguments: [Array(data)])
    }

    func makeUint8Array(from data: Data) -> JSValue? {
        return uint8ArrayFromArrayFunction?.call(withArguments: [Array(data)])
    }

    func postToWorker(_ message: JSValue) throws {
        guard let onmessage = context.globalObject.forProperty("onmessage") else {
            throw EngineError.evaluationFailed("worker onmessage not available")
        }
        lastException = nil
        let payload = makeObject()
        payload.setValue(message, forProperty: "data")
        _ = onmessage.call(withArguments: [payload])
        if let lastException {
            throw EngineError.evaluationFailed(lastException)
        }
    }

    @discardableResult
    func evaluate(script: String) throws -> JSValue? {
        lastException = nil
        let value = context.evaluateScript(script)
        if let lastException {
            throw EngineError.evaluationFailed(lastException)
        }
        return value
    }

    private func evaluateScript(at url: URL) throws {
        lastException = nil
        guard let script = try? String(contentsOf: url, encoding: .utf8) else {
            throw EngineError.scriptReadFailed(url)
        }
        _ = context.evaluateScript(script, withSourceURL: url)
        if let lastException {
            throw EngineError.evaluationFailed(lastException)
        }
    }

    private func installNativeBridges() {
        let postMessage: @convention(block) (JSValue, JSValue) -> Void = { [weak self] message, transfer in
            let transferArray = transfer.toArray() ?? []
            self?.onPostMessage?(message.toObject(), transferArray)
        }
        context.setObject(postMessage, forKeyedSubscript: "__nativePostMessage" as NSString)

        let log: @convention(block) (JSValue) -> Void = { [weak self] value in
            let normalized: Any = (value.isUndefined || value.isNull) ? NSNull() : (value.toObject() ?? NSNull())
            self?.onLog?(normalized)
        }
        context.setObject(log, forKeyedSubscript: "__nativeLog" as NSString)

        let random: @convention(block) (JSValue) -> JSValue = { value in
            let length = value.forProperty("length")?.toInt32() ?? 0
            guard length > 0 else { return value }
            var bytes = [UInt8](repeating: 0, count: Int(length))
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            for (index, byte) in bytes.enumerated() {
                value.setValue(Int(byte), at: index)
            }
            return value
        }
        context.setObject(random, forKeyedSubscript: "__nativeRandom" as NSString)

        let uuid: @convention(block) () -> String = {
            return UUID().uuidString
        }
        context.setObject(uuid, forKeyedSubscript: "__nativeUUID" as NSString)

        let atob: @convention(block) (String) -> String = { value in
            guard let data = Data(base64Encoded: value) else { return "" }
            return String(data: data, encoding: .isoLatin1) ?? ""
        }
        context.setObject(atob, forKeyedSubscript: "__nativeAtob" as NSString)

        let btoa: @convention(block) (String) -> String = { value in
            let data = value.data(using: .isoLatin1) ?? Data()
            return data.base64EncodedString()
        }
        context.setObject(btoa, forKeyedSubscript: "__nativeBtoa" as NSString)

        let textDecode: @convention(block) (JSValue, String) -> String = { [weak self] value, encoding in
            var source = value
            if value.forProperty("length")?.isUndefined ?? true,
               !(value.forProperty("byteLength")?.isUndefined ?? true),
               let bufferToArray = self?.uint8ArrayFromBufferFunction,
               let converted = bufferToArray.call(withArguments: [value]) {
                source = converted
            }
            let bytes = dataFromJSValue(source)
            let normalized = encoding.lowercased()
            let stringEncoding: String.Encoding
            if normalized.contains("utf-16be") {
                stringEncoding = .utf16BigEndian
            } else if normalized.contains("utf-16le") {
                stringEncoding = .utf16LittleEndian
            } else if normalized.contains("iso-8859-1") || normalized.contains("latin1") {
                stringEncoding = .isoLatin1
            } else {
                stringEncoding = .utf8
            }
            let decoded = String(data: bytes, encoding: stringEncoding) ?? ""
            if decoded.hasPrefix("\u{FEFF}") {
                return String(decoded.dropFirst())
            }
            return decoded
        }
        context.setObject(textDecode, forKeyedSubscript: "__nativeTextDecode" as NSString)

        let setTimeout: @convention(block) (JSValue, Int) -> Int = { [weak self] fn, ms in
            guard let self else { return 0 }
            let id = self.nextTimeoutId()
            let workItem = DispatchWorkItem { _ = fn.call(withArguments: []) }
            self.timeouts[id] = workItem
            self.queue.asyncAfter(deadline: .now() + .milliseconds(ms), execute: workItem)
            return id
        }
        context.setObject(setTimeout, forKeyedSubscript: "__nativeSetTimeout" as NSString)

        let clearTimeout: @convention(block) (Int) -> Void = { [weak self] id in
            guard let self else { return }
            self.timeouts.removeValue(forKey: id)?.cancel()
        }
        context.setObject(clearTimeout, forKeyedSubscript: "__nativeClearTimeout" as NSString)

        let setInterval: @convention(block) (JSValue, Int) -> Int = { [weak self] fn, ms in
            guard let self else { return 0 }
            let id = self.nextTimeoutId()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                _ = fn.call(withArguments: [])
                self.rescheduleInterval(id: id, fn: fn, ms: ms)
            }
            self.intervals[id] = workItem
            self.queue.asyncAfter(deadline: .now() + .milliseconds(ms), execute: workItem)
            return id
        }
        context.setObject(setInterval, forKeyedSubscript: "__nativeSetInterval" as NSString)

        let clearInterval: @convention(block) (Int) -> Void = { [weak self] id in
            guard let self else { return }
            self.intervals.removeValue(forKey: id)?.cancel()
        }
        context.setObject(clearInterval, forKeyedSubscript: "__nativeClearInterval" as NSString)
    }

    private func installHelpers() {
        bufferFromArrayFunction = context.evaluateScript(
            "(function(a){return new Uint8Array(a).buffer;})"
        )
        uint8ArrayFromArrayFunction = context.evaluateScript(
            "(function(a){return new Uint8Array(a);})"
        )
        uint8ArrayFromBufferFunction = context.evaluateScript(
            "(function(ab){return new Uint8Array(ab);})"
        )
    }

    private func nextTimeoutId() -> Int {
        let id = timeoutId
        timeoutId += 1
        return id
    }

    private func rescheduleInterval(id: Int, fn: JSValue, ms: Int) {
        guard intervals[id] != nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            _ = fn.call(withArguments: [])
            self.rescheduleInterval(id: id, fn: fn, ms: ms)
        }
        intervals[id] = workItem
        queue.asyncAfter(deadline: .now() + .milliseconds(ms), execute: workItem)
    }
}

private func dataFromJSValue(_ value: JSValue) -> Data {
    let length = value.forProperty("length")?.toInt32() ?? 0
    guard length > 0 else { return Data() }
    var bytes = [UInt8]()
    bytes.reserveCapacity(Int(length))
    for index in 0..<Int(length) {
        let byteValue = value.objectAtIndexedSubscript(index)?.toInt32() ?? 0
        bytes.append(UInt8(clamping: Int(byteValue)))
    }
    return Data(bytes)
}
