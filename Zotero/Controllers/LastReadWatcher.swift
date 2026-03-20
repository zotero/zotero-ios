//
//  LastReadWatcher.swift
//  Zotero
//
//  Created by Michal Rentka on 20.03.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift

final class LastReadWatcher {
    private unowned let dbStorage: DbStorage
    private var lastUpdate: (key: String, libraryId: LibraryIdentifier)?
    private var pendingUpdate: (key: String, libraryId: LibraryIdentifier, date: Date?)?
    private var timer: BackgroundTimer?
    private var observers: [Any] = []

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        observers = [
            NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.flushPendingAndStop()
            },
            NotificationCenter.default.addObserver(forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.flushPendingAndStop()
            },
            NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                self?.flushPendingAndStop()
            }
        ]
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func submit(key: String, libraryId: LibraryIdentifier, date: Date?) {
        if let pendingUpdate, timer?.state == .resumed {
            store(key: pendingUpdate.key, libraryId: pendingUpdate.libraryId, date: pendingUpdate.date)
        }
        store(key: key, libraryId: libraryId, date: date)
        lastUpdate = (key, libraryId)
        pendingUpdate = nil
        timer = nil
    }

    func submitAfterDelay(key: String, libraryId: LibraryIdentifier, date: Date?) {
        if lastUpdate?.key == key && lastUpdate?.libraryId == libraryId {
            pendingUpdate = (key, libraryId, date)
            guard timer == nil || timer?.state == .suspended else { return }
            let timer = BackgroundTimer(timeInterval: .seconds(300))
            timer.eventHandler = { [weak self] in
                self?.flushPendingAndStop()
            }
            self.timer = timer
            timer.resume()
        } else {
            if let pendingUpdate {
                store(key: pendingUpdate.key, libraryId: pendingUpdate.libraryId, date: pendingUpdate.date)
            }
            store(key: key, libraryId: libraryId, date: date)
            lastUpdate = (key, libraryId)
            pendingUpdate = nil
            timer = nil
        }
    }

    private func flushPendingAndStop() {
        if let pendingUpdate {
            store(key: pendingUpdate.key, libraryId: pendingUpdate.libraryId, date: pendingUpdate.date)
        }
        pendingUpdate = nil
        lastUpdate = nil
        timer = nil
    }

    private func store(key: String, libraryId: LibraryIdentifier, date: Date?) {
        do {
            try dbStorage.perform(request: StoreLastReadDateDbRequest(key: key, libraryId: libraryId, date: date), on: .main)
        } catch {
            DDLogError("LastReadWatcher: can't store last read date - \(error)")
        }
    }
}
