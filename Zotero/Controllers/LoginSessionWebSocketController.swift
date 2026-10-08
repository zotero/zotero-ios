//
//  LoginSessionWebSocketController.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 22/03/2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

final class LoginSessionWebSocketController: SubscriptionWebSocketController {
    private let jsonDecoder: JSONDecoder

    let loginObservable: PublishSubject<LoginWsResponse.Kind>

    static func topic(for sessionToken: String) -> String {
        "login-session:\(sessionToken)"
    }

    init() {
        jsonDecoder = JSONDecoder()
        loginObservable = PublishSubject()
        super.init(lowPowerModeController: nil)
    }

    func connect(sessionToken: String) {
        connect(subscriptionValue: sessionToken)
    }

    func disconnect(sessionToken: String?) {
        disconnect(subscriptionValue: sessionToken)
    }

    override var logCategory: String {
        "LoginSessionWebSocketController"
    }

    override func subscribe(to subscriptionValue: String, completion: @escaping (WebSocketController.Error?) -> Void) {
        transport.send(message: SubscribeWsMessage(topic: Self.topic(for: subscriptionValue)), responseEvent: .subscriptionCreated, completion: completion)
    }

    override func unsubscribe(from subscriptionValue: String, completion: @escaping (WebSocketController.Error?) -> Void) {
        transport.send(message: UnsubscribeWsMessage(topic: Self.topic(for: subscriptionValue)), responseEvent: .subscriptionDeleted, completion: completion)
    }

    override func handleTransportData(_ data: Data) {
        do {
            let event = try jsonDecoder.decode(WsResponse.self, from: data).event

            switch event {
            case .loginComplete, .loginCancelled:
                guard let response = try? jsonDecoder.decode(LoginWsResponse.self, from: data) else { return }
                loginObservable.on(.next(response.kind))

            case .connected, .subscriptionCreated, .subscriptionDeleted, .topicAdded, .topicRemoved, .topicUpdated:
                break
            }
        } catch let error {
            DDLogError("LoginSessionWebSocketController: received unknown message - \(error)")
        }
    }
}
