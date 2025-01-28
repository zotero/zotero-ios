//
//  PDFWorkerWebViewHandler.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 24/1/25.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import WebKit

import CocoaLumberjackSwift
import RxCocoa
import RxSwift

final class PDFWorkerWebViewHandler: WebViewHandler {
    /// Handlers for communication with JS in `webView`
    enum JSHandlers: String, CaseIterable {
        /// Handler used for reporting recognizer data.
        case recognizerData = "recognizerDataHandler"
        /// Handler used for reporting full text.
        case fullText = "fullTextHandler"
        /// Handler used to log JS debug info.
        case log = "logHandler"
    }

    enum PDFWorkerData {
        case recognizerData(data: [String: Any])
        case fullText(data: [String: Any])
    }

    private let disposeBag: DisposeBag
    let observable: PublishSubject<Result<PDFWorkerData, Swift.Error>>

    init(webView: WKWebView) {
        observable = PublishSubject()
        disposeBag = DisposeBag()

        super.init(webView: webView, javascriptHandlers: JSHandlers.allCases.map({ $0.rawValue }))

        receivedMessageHandler = { [weak self] name, body in
            self?.receiveMessage(name: name, body: body)
        }
    }

    override func initializeWebView() -> Single<()> {
        DDLogInfo("PDFWorkerWebViewHandler: initialize web view")
        let baseURL = Bundle.main.bundleURL.appendingPathComponent("Bundled/pdf_worker", isDirectory: true)
        return loadHTMLString(Self.htmlString, baseURL: baseURL)
            .flatMap { _ in
                Single.just(Void())
            }
    }

    func recognize(file: FileData) {
        performAfterInitialization()
            .flatMap { [weak self] _ -> Single<Any> in
                guard let self else { return .never() }
                let filePath = file.createUrl().path
                DDLogInfo("PDFWorkerWebViewHandler: call recognize js")
                return call(javascript: "recognize('\(filePath)');")
            }
            .subscribe(on: MainScheduler.instance)
            .observe(on: MainScheduler.instance)
            .subscribe(onFailure: { [weak self] error in
                DDLogError("PDFWorkerWebViewHandler: recognize failed - \(error)")
                self?.observable.on(.next(.failure(error)))
            })
            .disposed(by: disposeBag)
    }

    func getFullText(file: FileData) {
        performAfterInitialization()
            .flatMap { [weak self] _ -> Single<Any> in
                guard let self else { return .never() }
                let filePath = file.createUrl().path
                DDLogInfo("PDFWorkerWebViewHandler: call getFullText js")
                return call(javascript: "getFullText('\(filePath)');")
            }
            .subscribe(on: MainScheduler.instance)
            .observe(on: MainScheduler.instance)
            .subscribe(onFailure: { [weak self] error in
                DDLogError("PDFWorkerWebViewHandler: getFullText failed - \(error)")
                self?.observable.on(.next(.failure(error)))
            })
            .disposed(by: disposeBag)
    }

    /// Communication with JS in `webView`. The `webView` sends a message through one of the registered `JSHandlers`, which is received here.
    /// Each message contains a `messageId` in the body, which is used to identify the message in case a response is expected.
    private func receiveMessage(name: String, body: Any) {
        guard let handler = JSHandlers(rawValue: name) else { return }

        switch handler {
        case .recognizerData:
            guard let data = (body as? [String: Any])?["recognizerData"] as? [String: Any] else { return }
            observable.on(.next(.success(.recognizerData(data: data))))

        case .fullText:
            guard let data = (body as? [String: Any])?["fullText"] as? [String: Any] else { return }
            observable.on(.next(.success(.recognizerData(data: data))))

        case .log:
            DDLogInfo("JSLOG: \(body)")
        }
    }

    static let htmlString: String = """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>PDF Worker</title>
</head>
<body>
<script>
function log(message) {
  webkit.messageHandlers.logHandler.postMessage(message);
}

let promiseId = 0;
let waitingPromises = {};
let worker = new Worker('worker.js');

async function query(action, data, transfer) {
  return new Promise(function (resolve) {
    promiseId++;
    waitingPromises[promiseId] = resolve;
    worker.postMessage({ id: promiseId, action, data }, transfer);
  });
}

worker.onmessage = async function (e) {
  let message = e.data;
  window.webkit.messageHandlers.logHandler.postMessage('Message received', message);
  if (message.responseID) {
    let resolve = waitingPromises[message.responseID];
    if (resolve) {
      resolve(message.data);
    }
    return;
  }
  if (message.id) {
    window.webkit.messageHandlers.logHandler.postMessage('\thas id: ' + message.id);
    let respData = null;
    if (message.op === 'FetchBuiltInCMap') {
      respData = {
        compressionType: 1,
        cMapData: new Uint8Array(await (await fetch('/cmaps/' + message.data + '.bcmap')).arrayBuffer())
      };
    }
    worker.postMessage({ responseID: e.data.id, data: respData });
    return;
  }
}

async function fetchLocalFile(filePath) {
  log(`fetching ${filePath}`);
  let response = await fetch(filePath);
  log(`response: ${JSON.stringify(response)}`);
  let arrayBuffer = await response.arrayBuffer();
  return arrayBuffer.slice();
}

async function recognize(filePath) {
  try {
    let buf = await fetchLocalFile(filePath)
    let recognizerData = await query('getRecognizerData', { buf }, [buf]);
    webkit.messageHandlers.recognizerDataHandler.postMessage({"recognizerData": recognizerData});
  } catch (error) {
    log(`error: ${error}`);
    throw error;
  }
}

async function getFullText(filePath) {
  try {
    let buf = await fetchLocalFile(filePath)
    let fulltext = await query('getFulltext', { buf }, [buf]);
    webkit.messageHandlers.fullTextHandler.postMessage({"fullText": fulltext});
  } catch (error) {
    log(`error: ${error}`);
    throw error;
  }
}
</script>
</body>
</html>
"""
}
