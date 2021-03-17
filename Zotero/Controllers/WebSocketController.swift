//
//  WebSocketController.swift
//  Zotero
//
//  Created by Michal Rentka on 01.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxCocoa
import RxSwift
import Starscream

fileprivate struct Response {
    let timer: BackgroundTimer
    let completion: () -> Void

    static func create(timeout: DispatchTimeInterval, queue: DispatchQueue, completion: @escaping (WebSocketController.Error?) -> Void) -> Response {
        let timer = BackgroundTimer(timeInterval: timeout, queue: queue)
        timer.eventHandler = {
            completion(.timedOut)
        }
        timer.resume()

        return Response(timer: timer, completion: {
            timer.suspend()
            completion(nil)
        })
    }
}

final class WebSocketController {
    enum ConnectionState {
        case disconnected, connecting, subscribing, connected
    }

    enum Error: Swift.Error {
        case cantCreateMessage
        case timedOut
        case notConnected
    }

    private static let completionTimeout: Int = 1500 // miliseconds
    private static let messageTimeout: Int = 30
    private static let disconnectionTimeout: Int = 5
    private static let retryIntervals: [Int] = [
                                                2, 5, 10, 15, 30,      // first minute
                                                60, 60, 60, 60,        // every minute for 4 minutes
                                                120, 120, 120, 120,    // every 2 minutes for 8 minutes
                                                300, 300,              // every 5 minutes for 10 minutes
                                                600,                   // 10 minutes
                                                1200,                  // 20 minutes
                                                1800, 1800,            // 30 minutes for 1 hour
                                                3600, 3600, 3600,      // every hour for 3 hours
                                                14400, 14400, 14400,   // every 4 hours for 12 hours
                                                86400                  // 1 day
                                               ]

    private let url: URL
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder
    private let queue: DispatchQueue
    private unowned let dbStorage: DbStorage
    let observable: PublishSubject<ChangeWsResponse.Kind>

    private var apiKey: String?
    private var webSocket: WebSocket?
    private var responseListeners: [WsResponse.Event: Response]
    private(set) var connectionState: BehaviorRelay<ConnectionState>
    private var connectionRetryCount: Int
    private var connectionTimer: BackgroundTimer?
    private var completionAction: (() -> Void)?
    private var completionTimer: BackgroundTimer?

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.connectionState = BehaviorRelay(value: .disconnected)
        self.connectionRetryCount = 0
        self.responseListeners = [:]
        self.url = URL(string: "wss://stream.zotero.org")!
        self.jsonDecoder = JSONDecoder()
        self.jsonEncoder = JSONEncoder()
        self.queue = DispatchQueue(label: "org.zotero.WebSocketQueue", qos: .userInteractive)
        self.observable = PublishSubject()
    }

    // MARK: - Connection

    /// Attempts to connect to server and subscribe with given api key.
    /// - parameter apiKey: Api key to subscribe with
    /// - parameter completed: Completion block which is called after successful subscription or after first unsuccessful retry.
    func connect(apiKey: String, completed: (() -> Void)? = nil) {
        self.queue.async { [weak self] in
            self?._connect(apiKey: apiKey, completed: completed)
        }
    }

    private func _connect(apiKey: String, completed: (() -> Void)?) {
        switch self.connectionState.value {
        case .subscribing, .connected:
            DDLogWarn("WebSocketController: tried to connect while \(self.connectionState.value)")
            completed?()
            return
        case .connecting, .disconnected: break
        }

        DDLogInfo("WebSocketController: connect")

        // In case a reconnect was scheduled, suspend the timer
        self.connectionTimer?.suspend()
        self.connectionTimer = nil
        // Set internal state
        self.connectionState.accept(.connecting)
        self.apiKey = apiKey
        // Start observing connected message
        self.createResponse(for: .connected) { [weak self] error in
            self?.processConnectionResponse(with: error, apiKey: apiKey)
        }
        // Setup completion timeout, don't stop previous timer if completed is nil. Reconnect sets completion to nil.
        if let completed = completed {
            self.completionAction = completed

            let completionTimer = BackgroundTimer(timeInterval: .milliseconds(WebSocketController.completionTimeout), queue: self.queue)
            completionTimer.eventHandler = { [weak self] in
                guard let `self` = self else { return }
                self.completionAction?()
                self.completionAction = nil
                self.completionTimer = nil
            }
            completionTimer.resume()
            self.completionTimer = completionTimer
        }
        // Start websocket connection
        let webSocket = WebSocket(request: URLRequest(url: self.url))
        webSocket.callbackQueue = self.queue
        webSocket.respondToPingWithPong = true
        webSocket.onEvent = { [weak self] event in
            self?.handle(event: event)
        }
        webSocket.connect()
        self.webSocket = webSocket
    }

    /// Processes response of connection or subscription. If no error occured, proceed with subscription or completion block. Otherwise retry connection/subscription as needed.
    /// - parameter error: Error if any occured after connection/subscription, nil otherwise.
    /// - parameter apiKey: Api key to subscribe to after successful connection.
    /// - parameter completed: Completion block called after successful subscription or after first unsuccessful retry.
    private func processConnectionResponse(with error: Error?, apiKey: String) {
        if let error = error {
            DDLogError("WebSocketController: connection error - \(error)")
            self.retryConnection(apiKey: apiKey)
            return
        }

        switch self.connectionState.value {
        case .connecting:
            self.connectionState.accept(.subscribing)
            DDLogInfo("WebSocketController: subscribe")
            self.subscribe(apiKey: apiKey) { [weak self] error in
                self?.processConnectionResponse(with: error, apiKey: apiKey)
            }

        case .subscribing:
            DDLogInfo("WebSocketController: connected & subscribed")

            self.connectionState.accept(.connected)
            self.connectionRetryCount = 0
            self.connectionTimer?.suspend()
            self.connectionTimer = nil
            self.completionTimer?.suspend()
            self.completionTimer = nil

            self.completionAction?()
            self.completionAction = nil

        case .connected, .disconnected:
            DDLogWarn("WebSocketController: connection response processed while already \(self.connectionState.value)")
            self.completionAction?()
            self.completionAction = nil
        }

        return
    }

    /// Retries connection after unsuccessful attempt.
    private func retryConnection(apiKey: String) {
        switch self.connectionState.value {
        case .connected, .disconnected:
            DDLogWarn("WebSocketController: tried to retry connection while already \(self.connectionState.value)")
            return

        default: break
        }

        let interval = WebSocketController.retryIntervals[min(self.connectionRetryCount, (WebSocketController.retryIntervals.count - 1))]
        self.connectionRetryCount += 1
        DDLogInfo("WebSocketController: schedule retry attempt \(self.connectionRetryCount) interval \(interval)")

        let timer = BackgroundTimer(timeInterval: .seconds(interval), queue: self.queue)
        timer.eventHandler = { [weak self] in
            guard let `self` = self else { return }

            switch self.connectionState.value {
            case .connecting, .disconnected:
                self._connect(apiKey: apiKey, completed: nil)
            case .subscribing:
                self.subscribe(apiKey: apiKey, completion: { [weak self] error in
                    self?.processConnectionResponse(with: error, apiKey: apiKey)
                })
            case .connected: break
            }

            self.connectionTimer = nil
        }
        timer.resume()
        self.connectionTimer = timer
    }

    /// Reconnects to server after disconnection.
    private func reconnect() {
        guard self.connectionState.value == .connected else { return }

        self.connectionState.accept(.disconnected)

        guard let apiKey = self.apiKey else {
            DDLogError("WebSocketController: attempting reconnect, but apiKey is missing")
            return
        }

        DDLogInfo("WebSocketController: schedule reconnect")

        let timer = BackgroundTimer(timeInterval: .seconds(WebSocketController.disconnectionTimeout), queue: self.queue)
        timer.eventHandler = { [weak self] in
            self?._connect(apiKey: apiKey, completed: nil)
            self?.connectionTimer = nil
        }
        timer.resume()
        self.connectionTimer = timer
    }

    /// Unsubscribes from api key if provided and disconnects from server.
    /// - parameter apiKey: Api key to unsubscribe from. If none is provided, websocket is just disconnected.
    func disconnect(apiKey: String?) {
        self.queue.async { [weak self] in
            guard let `self` = self, self.connectionState.value != .disconnected else { return }

            if let key = apiKey, self.connectionState.value == .connected {
                self.unsubscribe(apiKey: key)
            } else {
                self.disconnect()
            }
        }
    }

    // MARK: - Subscription

    /// Subscribes for changes for given api key.
    /// - parameter apiKey: Api key to subscribe to.
    private func subscribe(apiKey: String, completion: @escaping (Error?) -> Void) {
        self.send(message: SubscribeWsMessage(apiKey: apiKey), responseEvent: .subscriptionCreated, completion: completion)
    }

    /// Unsubscribes from changes for given api key.
    /// - parameter apiKey: Api key to unsubscribe from.
    private func unsubscribe(apiKey: String) {
        self.send(message: UnsubscribeWsMessage(apiKey: apiKey), responseEvent: .subscriptionDeleted, completion: { [weak self] _ in
            // If unsubscription was not successful, just disconnect anyway
            self?.disconnect()
        })
    }

    // MARK: - Helpers

    /// Handles received websocket event.
    /// - parameter event: Websocket event to process.
    private func handle(event: WebSocketEvent) {
        DDLogInfo("WebSocketController: WS event - \(event)")

        switch event {
        case .ping, .pong, .viabilityChanged, .reconnectSuggested, .connected, .cancelled, .error: break

        case .disconnected:
            self.reconnect()

        case .binary(let data):
            self.handle(data: data)

        case .text(let string):
            let data = string.data(using: .utf8) ?? Data()
            self.handle(data: data)
        }
    }

    /// Handles received data. If response event is registered, appropriate completion block is called. Otherwise the received event is handled.
    private func handle(data: Data) {
        do {
            let event = try self.jsonDecoder.decode(WsResponse.self, from: data).event

            if let response = self.responseListeners[event] {
                response.completion()
                return
            }

            DDLogInfo("WebSocketController: handle event - \(event)")

            switch event {
            case .topicAdded, .topicRemoved, .topicUpdated:
                guard let changeResponse = (try? self.jsonDecoder.decode(ChangeWsResponse.self, from: data)) else { return }
                self.publishChangeIfNeeded(response: changeResponse)

            case .connected, .subscriptionCreated, .subscriptionDeleted: break
            }

        } catch let error {
            let message = String(data: data, encoding: .utf8) ?? ""
            DDLogError("WebSocketController: received unknown message - \(error). Original message: \(message)")
        }
    }

    private func publishChangeIfNeeded(response: ChangeWsResponse) {
        switch response.type {
        case .translators:
            self.observable.on(.next(response.type))

        case .library(let libraryId, let version):
            guard let version = version else {
                // If version was not received in message, publish change.
                self.observable.on(.next(response.type))
                return
            }

            // If version was received in message, check whether it's higher than local one.

            do {
                let localVersion = try self.dbStorage.createCoordinator().perform(request: ReadVersionDbRequest(libraryId: libraryId))
                guard localVersion < version else { return }
                self.observable.on(.next(response.type))
            } catch let error {
                DDLogWarn("WebSocketController: can't read version for received message - \(error)")
            }
        }
    }

    /// Creates a response listener for given event.
    /// - parameter event: Event to listen to.
    /// - parameter completion: Completion block to call after event is received.
    private func createResponse(for event: WsResponse.Event, completion: @escaping (Error?) -> Void) {
        let response = Response.create(timeout: .seconds(WebSocketController.messageTimeout), queue: self.queue, completion: { [weak self] error in
            self?.responseListeners[event] = nil
            completion(error)
        })
        self.responseListeners[event] = response
    }

    /// Adds a response listener to queue and sends given message.
    /// - parameter message: Message to send
    /// - parameter responseEvent: Event which is a response to this message.
    /// - parameter completion: Completion block called after response message is received.
    private func send<Message: Encodable>(message: Message, responseEvent: WsResponse.Event, completion: @escaping (Error?) -> Void) {
        guard self.connectionState.value != .disconnected, let webSocket = self.webSocket else {
            completion(.notConnected)
            return
        }

        do {
            let data = try self.jsonEncoder.encode(message)
            let string = String(data: data, encoding: .utf8) ?? ""

            DDLogInfo("WebSocketController: send message - \(string)")

            self.createResponse(for: responseEvent, completion: completion)
            webSocket.write(string: string)
        } catch let error {
            DDLogError("WebSocketController: message error (\(message)) - \(error)")
            completion(.cantCreateMessage)
        }
    }

    /// Disconnects from websocket and cleans up.
    private func disconnect() {
        // Set state to disconnected
        self.connectionState.accept(.disconnected)
        // Reset retry counter
        self.connectionRetryCount = 0
        // Suspend connection timer if connection is in progress
        self.connectionTimer?.suspend()
        self.connectionTimer = nil
        // Suspend completion timer if completion exists
        self.completionTimer?.suspend()
        self.completionTimer = nil
        // Suspend all response listeners if there are any
        for (_, response) in self.responseListeners {
            response.timer.suspend()
        }
        self.responseListeners = [:]
        // Disconnect from websocket if connected
        self.webSocket?.disconnect()
        self.webSocket = nil
        // Clear current api key
        self.apiKey = nil
    }
}
