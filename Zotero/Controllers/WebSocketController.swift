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

final class WebSocketController {
    private struct Response {
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

    enum ConnectionState: Equatable {
        case disconnected, connecting, connected
    }

    enum Error: Swift.Error {
        case cantCreateMessage
        case timedOut
        case notConnected
    }

    fileprivate static let retryIntervals: [Int] = [
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

    private static let completionTimeout: Int = 1500 // miliseconds
    private static let messageTimeout: Int = 30
    private static let disconnectionTimeout: Int = 5

    private let queue: DispatchQueue
    private let queueKey: DispatchSpecificKey<String>
    private let queueLabel: String
    fileprivate let messageObservable: PublishSubject<Data>
    fileprivate private(set) var connectionState: BehaviorRelay<ConnectionState>

    private let url: URL
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder
    private let scheduler: SerialDispatchQueueScheduler
    private let lowPowerModeController: LowPowerModeController?
    private let disposeBag: DisposeBag

    private var shouldStayConnected: Bool
    private var redactedValues: Set<String>
    private var webSocket: WebSocket?
    private var responseListeners: [WsResponse.Event: Response]
    private var connectionRetryCount: Int
    private var connectionTimer: BackgroundTimer?
    private var completionAction: (() -> Void)?
    private var completionTimer: BackgroundTimer?

    init(lowPowerModeController: LowPowerModeController?) {
        let uuidString = UUID().uuidString
        queueLabel = "org.zotero.WebSocketQueue." + uuidString
        let queue = DispatchQueue(label: queueLabel, qos: .userInteractive)
        queueKey = DispatchSpecificKey<String>()
        queue.setSpecific(key: queueKey, value: queueLabel)
        self.lowPowerModeController = lowPowerModeController
        connectionState = BehaviorRelay(value: .disconnected)
        connectionRetryCount = 0
        responseListeners = [:]
        url = URL(string: "wss://stream.zotero.org")!
        jsonDecoder = JSONDecoder()
        jsonEncoder = JSONEncoder()
        self.queue = queue
        scheduler = SerialDispatchQueueScheduler(queue: queue, internalSerialQueueName: "org.zotero.WebSocketScheduler." + uuidString)
        messageObservable = PublishSubject()
        disposeBag = DisposeBag()
        shouldStayConnected = false
        redactedValues = []

        lowPowerModeController?.observable
            .observe(on: scheduler)
            .subscribe(onNext: { [weak self] isEnabled in
                self?.lowPowerModeChanged(isEnabled: isEnabled)
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Connection

    func connect(completed: (() -> Void)? = nil) {
        perform { [weak self] in
            self?.connectInternal(completed: completed)
        }
    }

    private func connectInternal(completed: (() -> Void)?) {
        switch connectionState.value {
        case .connected:
            DDLogWarn("WebSocketController: tried to connect while \(connectionState.value)")
            completed?()
            return

        case .connecting, .disconnected:
            break
        }

        shouldStayConnected = true

        guard lowPowerModeController?.lowPowerModeEnabled != true else {
            completed?()
            return
        }

        DDLogInfo("WebSocketController: connect")

        // In case a reconnect was scheduled, suspend the timer
        connectionTimer?.suspend()
        connectionTimer = nil
        // Set internal state
        connectionState.accept(.connecting)
        // Start observing connected message
        createResponse(for: .connected) { [weak self] error in
            self?.processConnectionResponse(with: error)
        }
        // Setup completion timeout, don't stop previous timer if completed is nil. Reconnect sets completion to nil.
        if let completed {
            completionAction = completed

            let completionTimer = BackgroundTimer(timeInterval: .milliseconds(WebSocketController.completionTimeout), queue: queue)
            completionTimer.eventHandler = { [weak self] in
                guard let self else { return }
                completionAction?()
                completionAction = nil
                self.completionTimer = nil
            }
            completionTimer.resume()
            self.completionTimer = completionTimer
        }
        // Start websocket connection
        let webSocket = WebSocket(request: URLRequest(url: url))
        webSocket.callbackQueue = queue
        webSocket.respondToPingWithPong = true
        webSocket.onEvent = { [weak self] event in
            self?.handle(event: event)
        }
        webSocket.connect()
        self.webSocket = webSocket
    }

    /// Processes response of connection. If no error occured, proceed with completion block. Otherwise retry connection as needed.
    /// - parameter error: Error if any occured after connection, nil otherwise.
    private func processConnectionResponse(with error: Error?) {
        if let error {
            DDLogError("WebSocketController: connection error - \(error)")
            retryConnection()
            return
        }

        switch connectionState.value {
        case .connecting:
            DDLogInfo("WebSocketController: connected")

            connectionState.accept(.connected)
            connectionRetryCount = 0
            connectionTimer?.suspend()
            connectionTimer = nil
            completionTimer?.suspend()
            completionTimer = nil

            completionAction?()
            completionAction = nil

        case .connected, .disconnected:
            DDLogWarn("WebSocketController: connection response processed while already \(connectionState.value)")
            completionAction?()
            completionAction = nil
        }
    }

    /// Retries connection after unsuccessful attempt.
    private func retryConnection() {
        switch connectionState.value {
        case .connected, .disconnected:
            DDLogWarn("WebSocketController: tried to retry connection while already \(connectionState.value)")
            return

        case .connecting:
            break
        }

        let interval = WebSocketController.retryIntervals[min(connectionRetryCount, (WebSocketController.retryIntervals.count - 1))]
        connectionRetryCount += 1
        DDLogInfo("WebSocketController: schedule retry attempt \(connectionRetryCount) interval \(interval)")

        let timer = BackgroundTimer(timeInterval: .seconds(interval), queue: queue)
        timer.eventHandler = { [weak self] in
            guard let self else { return }
            guard shouldStayConnected else {
                connectionTimer = nil
                return
            }

            switch connectionState.value {
            case .disconnected, .connecting:
                connectInternal(completed: nil)

            case .connected:
                break
            }

            connectionTimer = nil
        }
        timer.resume()
        connectionTimer = timer
    }

    /// Reconnects to server after disconnection.
    private func reconnect() {
        guard connectionState.value == .connected else { return }

        connectionState.accept(.disconnected)

        guard shouldStayConnected else {
            DDLogWarn("WebSocketController: websocket disconnected without reconnect intent")
            return
        }

        DDLogInfo("WebSocketController: schedule reconnect")

        let timer = BackgroundTimer(timeInterval: .seconds(WebSocketController.disconnectionTimeout), queue: queue)
        timer.eventHandler = { [weak self] in
            guard let self else { return }
            connectInternal(completed: nil)
            connectionTimer = nil
        }
        timer.resume()
        connectionTimer = timer
    }

    /// Disconnects from server.
    func disconnect() {
        perform { [weak self] in
            guard let self else { return }
            shouldStayConnected = false
            disconnectInternal()
        }
    }

    /// Disconnects from websocket and cleans up.
    private func disconnectInternal() {
        guard connectionState.value != .disconnected else { return }
        // Set state to disconnected
        connectionState.accept(.disconnected)
        // Reset retry counter
        connectionRetryCount = 0
        // Suspend connection timer if connection is in progress
        connectionTimer?.suspend()
        connectionTimer = nil
        // Suspend completion timer if completion exists
        completionTimer?.suspend()
        completionTimer = nil
        // Suspend all response listeners if there are any
        for (_, response) in responseListeners {
            response.timer.suspend()
        }
        responseListeners = [:]
        // Disconnect from websocket if connected
        webSocket?.disconnect()
        webSocket = nil
    }

    // MARK: - Messaging

    func send<Message: Encodable>(message: Message, responseEvent: WsResponse.Event, completion: @escaping (Error?) -> Void) {
        perform { [weak self] in
            self?.sendInternal(message: message, responseEvent: responseEvent, completion: completion)
        }
    }

    /// Adds a response listener to queue and sends given message.
    /// - parameter message: Message to send
    /// - parameter responseEvent: Event which is a response to this message.
    /// - parameter completion: Completion block called after response message is received.
    private func sendInternal<Message: Encodable>(message: Message, responseEvent: WsResponse.Event, completion: @escaping (Error?) -> Void) {
        guard connectionState.value != .disconnected, let webSocket else {
            completion(.notConnected)
            return
        }

        do {
            let data = try jsonEncoder.encode(message)
            let string = String(data: data, encoding: .utf8) ?? ""

            DDLogInfo("WebSocketController: send message - \(redact(logMessage: string))")

            createResponse(for: responseEvent, completion: completion)
            webSocket.write(string: string)
        } catch let error {
            DDLogError("WebSocketController: message error (\(redact(logMessage: "\(message)")) - \(error)")
            completion(.cantCreateMessage)
        }
    }

    fileprivate func setRedactedValues(_ values: Set<String>) {
        perform { [weak self] in
            self?.redactedValues = values
        }
    }

    fileprivate func perform(_ action: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) == queueLabel {
            action()
        } else {
            queue.async(execute: action)
        }
    }

    fileprivate func createTimer(timeInterval: DispatchTimeInterval, eventHandler: @escaping () -> Void) -> BackgroundTimer {
        let timer = BackgroundTimer(timeInterval: timeInterval, queue: queue)
        timer.eventHandler = eventHandler
        return timer
    }

    fileprivate func performDbRequest<Request: DbResponseRequest>(_ request: Request, in dbStorage: DbStorage, invalidateRealm: Bool) throws -> Request.Response {
        try dbStorage.perform(request: request, on: queue, invalidateRealm: invalidateRealm)
    }

    // MARK: - Helpers

    /// Handles received websocket event.
    /// - parameter event: Websocket event to process.
    private func handle(event: WebSocketEvent) {
        DDLogInfo("WebSocketController: WS event - \(redact(logMessage: "\(event)"))")

        switch event {
        case .ping, .pong, .viabilityChanged, .reconnectSuggested, .connected, .cancelled, .error, .peerClosed:
            break

        case .disconnected:
            reconnect()

        case .binary(let data):
            handle(data: data)

        case .text(let string):
            let data = string.data(using: .utf8) ?? Data()
            handle(data: data)
        }
    }

    /// Handles received data. If response event is registered, appropriate completion block is called. Otherwise the received event is handled.
    private func handle(data: Data) {
        do {
            let event = try jsonDecoder.decode(WsResponse.self, from: data).event

            if let response = responseListeners[event] {
                response.completion()
                return
            }

            DDLogInfo("WebSocketController: handle event - \(redact(logMessage: "\(event)"))")
            messageObservable.on(.next(data))
        } catch let error {
            let message = String(data: data, encoding: .utf8) ?? ""
            DDLogError("WebSocketController: received unknown message - \(error). Original message: \(redact(logMessage: message))")
        }
    }

    /// Creates a response listener for given event.
    /// - parameter event: Event to listen to.
    /// - parameter completion: Completion block to call after event is received.
    private func createResponse(for event: WsResponse.Event, completion: @escaping (Error?) -> Void) {
        let response = Response.create(timeout: .seconds(WebSocketController.messageTimeout), queue: queue, completion: { [weak self] error in
            self?.responseListeners[event] = nil
            completion(error)
        })
        responseListeners[event] = response
    }

    private func redact(logMessage: String) -> String {
        return redactedValues.reduce(logMessage) { partial, value in
            partial.replacingOccurrences(of: value, with: "<redacted>")
        }
    }

    // MARK: - Low Power Mode

    private func lowPowerModeChanged(isEnabled: Bool) {
        guard connectionState.value != .disconnected else { return }
        if isEnabled {
            disconnectInternal()
        } else if shouldStayConnected {
            connectInternal(completed: nil)
        }
    }
}

class SubscriptionWebSocketController {
    private enum SubscriptionState {
        case disconnected, subscribing, subscribed
    }

    let transport: WebSocketController
    private let disposeBag: DisposeBag

    private var subscriptionValue: String?
    private var subscriptionState: SubscriptionState
    private var retryCount: Int
    private var retryTimer: BackgroundTimer?
    private var completionAction: (() -> Void)?

    init(lowPowerModeController: LowPowerModeController?) {
        transport = WebSocketController(lowPowerModeController: lowPowerModeController)
        disposeBag = DisposeBag()
        subscriptionState = .disconnected
        retryCount = 0

        transport.connectionState
            .asObservable()
            .distinctUntilChanged()
            .subscribe(onNext: { [weak self] state in
                self?.connectionStateChanged(to: state)
            })
            .disposed(by: disposeBag)

        transport.messageObservable
            .subscribe(onNext: { [weak self] data in
                self?.handleTransportData(data)
            })
            .disposed(by: disposeBag)
    }

    func connect(subscriptionValue: String, completed: (() -> Void)? = nil) {
        transport.perform { [weak self] in
            guard let self else { return }
            self.subscriptionValue = subscriptionValue
            subscriptionState = .disconnected
            completionAction = completed
            transport.setRedactedValues([subscriptionValue])

            if transport.connectionState.value == .connected {
                subscribeIfNeeded()
                return
            }

            transport.connect()
        }
    }

    func disconnect(subscriptionValue: String? = nil) {
        transport.perform { [weak self] in
            guard let self else { return }

            completionAction = nil
            resetRetryState()

            let subscriptionValue = subscriptionValue ?? self.subscriptionValue
            guard let subscriptionValue, transport.connectionState.value == .connected else {
                clearSubscription()
                transport.disconnect()
                return
            }

            unsubscribe(from: subscriptionValue) { [weak self] _ in
                guard let self else { return }
                clearSubscription()
                transport.disconnect()
            }
        }
    }

    func handleTransportData(_ data: Data) {}

    var logCategory: String {
        fatalError("Override logCategory")
    }

    func subscribe(to subscriptionValue: String, completion: @escaping (WebSocketController.Error?) -> Void) {
        fatalError("Override subscribe(to:completion:)")
    }

    func unsubscribe(from subscriptionValue: String, completion: @escaping (WebSocketController.Error?) -> Void) {
        fatalError("Override unsubscribe(from:completion:)")
    }

    func didSubscribe() {}

    func performDbRequest<Request: DbResponseRequest>(_ request: Request, in dbStorage: DbStorage, invalidateRealm: Bool) throws -> Request.Response {
        try transport.performDbRequest(request, in: dbStorage, invalidateRealm: invalidateRealm)
    }

    private func connectionStateChanged(to state: WebSocketController.ConnectionState) {
        guard subscriptionValue != nil else { return }

        switch state {
        case .connected:
            subscribeIfNeeded()

        case .connecting, .disconnected:
            subscriptionState = .disconnected
        }
    }

    private func subscribeIfNeeded() {
        guard let subscriptionValue else { return }
        guard subscriptionState != .subscribing else { return }

        subscriptionState = .subscribing
        DDLogInfo("\(logCategory): subscribe")

        subscribe(to: subscriptionValue) { [weak self] error in
            self?.processSubscriptionResponse(with: error)
        }
    }

    private func processSubscriptionResponse(with error: WebSocketController.Error?) {
        if let error {
            DDLogError("\(logCategory): subscription error - \(error)")
            subscriptionState = .disconnected
            retrySubscriptionIfNeeded()
            return
        }

        DDLogInfo("\(logCategory): connected & subscribed")
        subscriptionState = .subscribed
        resetRetryState()
        didSubscribe()
        completionAction?()
        completionAction = nil
    }

    private func retrySubscriptionIfNeeded() {
        guard subscriptionValue != nil else { return }

        let interval = WebSocketController.retryIntervals[min(retryCount, WebSocketController.retryIntervals.count - 1)]
        retryCount += 1
        DDLogInfo("\(logCategory): schedule retry attempt \(retryCount) interval \(interval)")

        let timer = transport.createTimer(timeInterval: .seconds(interval)) { [weak self] in
            guard let self else { return }
            defer { retryTimer = nil }
            guard subscriptionValue != nil else { return }

            switch transport.connectionState.value {
            case .connected:
                subscribeIfNeeded()

            case .connecting:
                break

            case .disconnected:
                transport.connect()
            }
        }
        timer.resume()
        retryTimer = timer
    }

    private func resetRetryState() {
        retryCount = 0
        retryTimer?.suspend()
        retryTimer = nil
    }

    private func clearSubscription() {
        subscriptionValue = nil
        subscriptionState = .disconnected
        transport.setRedactedValues([])
    }
}
