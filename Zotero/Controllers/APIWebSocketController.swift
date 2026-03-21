//
//  APIWebSocketController.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 22/03/2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

final class APIWebSocketController: SubscriptionWebSocketController {
    private let jsonDecoder: JSONDecoder
    private unowned let dbStorage: DbStorage

    let observable: PublishSubject<ChangeWsResponse.Kind>

    init(dbStorage: DbStorage, lowPowerModeController: LowPowerModeController) {
        jsonDecoder = JSONDecoder()
        self.dbStorage = dbStorage
        observable = PublishSubject()
        super.init(lowPowerModeController: lowPowerModeController)
    }

    func connect(apiKey: String, completed: (() -> Void)? = nil) {
        connect(subscriptionValue: apiKey, completed: completed)
    }

    func disconnect(apiKey: String?) {
        disconnect(subscriptionValue: apiKey)
    }

    override var logCategory: String {
        "APIWebSocketController"
    }

    override func subscribe(to subscriptionValue: String, completion: @escaping (WebSocketController.Error?) -> Void) {
        transport.send(message: SubscribeWsMessage(apiKey: subscriptionValue), responseEvent: .subscriptionCreated, completion: completion)
    }

    override func unsubscribe(from subscriptionValue: String, completion: @escaping (WebSocketController.Error?) -> Void) {
        transport.send(message: UnsubscribeWsMessage(apiKey: subscriptionValue), responseEvent: .subscriptionDeleted, completion: completion)
    }

    override func handleTransportData(_ data: Data) {
        do {
            let event = try jsonDecoder.decode(WsResponse.self, from: data).event

            switch event {
            case .topicAdded, .topicRemoved, .topicUpdated:
                guard let changeResponse = try? jsonDecoder.decode(ChangeWsResponse.self, from: data) else { return }
                publishChangeIfNeeded(response: changeResponse)

            case .connected, .subscriptionCreated, .subscriptionDeleted, .loginComplete:
                break
            }
        } catch let error {
            DDLogError("APIWebSocketController: received unknown message - \(error)")
        }
    }

    private func publishChangeIfNeeded(response: ChangeWsResponse) {
        switch response.type {
        case .translators:
            observable.on(.next(response.type))

        case .library(let libraryId, let version):
            guard let version else {
                // If version was not received in message, publish change.
                observable.on(.next(response.type))
                return
            }

            // If version was received in message, check whether it's higher than local one.
            do {
                let localVersion = try performDbRequest(ReadVersionDbRequest(libraryId: libraryId), in: dbStorage, invalidateRealm: true)
                guard localVersion < version else { return }
                observable.on(.next(response.type))
            } catch let error {
                DDLogWarn("APIWebSocketController: can't read version for received message - \(error)")
            }
        }
    }
}
