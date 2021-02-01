//
//  WebSocketController.swift
//  Zotero
//
//  Created by Michal Rentka on 01.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

class WebSocketController {
    enum Error: Swift.Error {
        case cantConvertStringToData
        case missingApiKeyOnSubscription
    }

    private let session: URLSession
    private let url: URL
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder

    private var task: URLSessionWebSocketTask!
    private var apiKey: String?
    private var connectionCompletion: (() -> Void)?

    init() {
        self.session = URLSession(configuration: .default)
        self.url = URL(string: "wss://stream.zotero.org")!
        self.jsonDecoder = JSONDecoder()
        self.jsonEncoder = JSONEncoder()
    }

    // MARK: - Connection

    /// Attempts to connect to server and subscribe with given api key.
    /// - parameter apiKey: Api key to subscribe with
    /// - parameter completed: Completion block which is called after successful subscription or after first unsuccessful retry.
    func connect(apiKey: String, completed: @escaping () -> Void) {
        self.connectionCompletion = completed
        self.apiKey = apiKey

        self.task = self.session.webSocketTask(with: self.url)
        self.startListening()
        self.task.resume()
    }

    func disconnect(apiKey: String? = nil) {
        if let key = apiKey {
            self.unsubscribe(apiKey: key)
        } else {
            self.task.cancel(with: .goingAway, reason: nil)
        }
    }

    // MARK: - Sending

    private func subscribe(apiKey: String) {
        self.send(message: SubscribeWsMessage(apiKey: apiKey)) { [weak self] error in
            if let error = error {
                // TODO: - handle error
            }
        }
    }

    private func unsubscribe(apiKey: String) {
        self.send(message: UnsubscribeWsMessage(apiKey: apiKey)) { [weak self] error in
            if let error = error {
                // TODO: - handle error
            }
        }
    }

    private func send<Message: Encodable>(message: Message, completion: @escaping (Swift.Error?) -> Void) {
        do {
            let data = try self.jsonEncoder.encode(message)
            self.task.send(.data(data), completionHandler: { error in
                if let error = error {
                    DDLogError("WebSocketController: message error (\(message)) - \(error)")
                }
                completion(error)
            })
        } catch let error {
            DDLogError("WebSocketController: message error (\(message)) - \(error)")
            completion(error)
        }
    }

    // MARK: - Receiving

    private func startListening() {
        self.task.receive { result in
            switch result {
            case .failure(let error):
                self.received(error: error)

            case .success(let message):
                switch message {
                case .data(let data):
                    self.received(data: data)

                case .string(let string):
                    if let data = string.data(using: .utf8) {
                        self.received(data: data)
                    } else {
                        self.received(error: Error.cantConvertStringToData)
                    }

                @unknown default:
                    DDLogError("WebSocketController: received unknown message type")
                }
            }
        }
    }

    private func received(data: Data) {
        do {
            let event = try self.jsonDecoder.decode(WsResponse.self, from: data).event
            self.handle(event: event)
        } catch let error {
            self.received(error: error)
        }
    }

    private func handle(event: WsResponse.Event) {
        switch event {
        case .connected:
            if let apiKey = self.apiKey {
                self.subscribe(apiKey: apiKey)
            } else {
                self.received(error: Error.missingApiKeyOnSubscription)
            }

        case .subscriptionCreated:
            // Report successful connection
            self.connectionCompletion?()
            // Clear tmp data
            self.connectionCompletion = nil
            self.apiKey = nil

        case .subscriptionDeleted:
            // Unsubscribed, cancel connection
            self.task.cancel(with: .goingAway, reason: nil)
        }
    }

    private func received(error: Swift.Error) {
        DDLogError("WebSocketController: received error - \(error)")

        if let error = error as? Error {
            switch error {
            case .missingApiKeyOnSubscription:
                // TODO: - retry subscription
            break

            case .cantConvertStringToData:
                // TODO: - ?
            break
            }

            return
        }

        if let error = error as? WsResponse.Error {

            return
        }
    }
}
