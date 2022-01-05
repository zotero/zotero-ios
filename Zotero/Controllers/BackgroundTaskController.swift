//
//  BackgroundTaskController.swift
//  Zotero
//
//  Created by Michal Rentka on 13.12.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct BackgroundTask {
    fileprivate let taskId: UIBackgroundTaskIdentifier
    fileprivate let expirationHandler: (() -> Void)?
}

final class BackgroundTaskController {
    private let queue: DispatchQueue

    private var tasks: [UIBackgroundTaskIdentifier: BackgroundTask] = [:]

    init() {
        self.queue = DispatchQueue(label: "org.zotero.BackgroundTaskController", qos: .userInteractive)
    }

    /// Starts background task in the main app. We can limit this to the main app, because the share extension is always closed after the upload
    /// is started, so the upload will be finished in the main app.
    func start(task taskAction: @escaping (BackgroundTask) -> Void, expirationHandler: (() -> Void)?) {
        let task: BackgroundTask

        #if MAINAPP
        let taskId = UIApplication.shared.beginBackgroundTask(withName: "org.zotero.finishUpload.\(UUID().uuidString)") { [weak self] in
            self?.queue.sync {
                self?.expireTasks()
            }
        }
        task = BackgroundTask(taskId: taskId, expirationHandler: expirationHandler)
        #else
        let taskId = UIBackgroundTaskIdentifier(rawValue: .random(in: 0..<Int.max))
        task = BackgroundTask(taskId: taskId, expirationHandler: expirationHandler)

        let processInfo = ProcessInfo()
        processInfo.performExpiringActivity(withReason: "org.zotero.finishUpload.\(UUID().uuidString)") { [weak self] expired in
            if expired {
                self?.queue.sync {
                    self?.expireTasks()
                }
            } else {
                taskAction(task)
            }
        }
        #endif

        self.queue.async(flags: .barrier) { [weak self] in
            self?.tasks[taskId] = task
        }

        #if MAINAPP
        taskAction(task)
        #endif
    }

    /// Ends the background task in the main app.
    func end(task: BackgroundTask) {
        self.queue.async(flags: .barrier) { [weak self] in
            self?.tasks[task.taskId] = nil
        }
        #if MAINAPP
        UIApplication.shared.endBackgroundTask(task.taskId)
        #endif
    }

    private func expireTasks() {
        guard !self.tasks.isEmpty else { return }

        let tasks = self.tasks

        // Clear tasks so that next expiration doesn't trigger the same tasks
        self.queue.async(flags: .barrier) { [weak self] in
            self?.tasks = [:]
        }

        // Perform all expiration handlers
        for task in tasks.values {
            task.expirationHandler?()
        }

        // End all tasks
        #if MAINAPP
        for task in tasks.values {
            UIApplication.shared.endBackgroundTask(task.taskId)
        }
        #endif
    }
}
