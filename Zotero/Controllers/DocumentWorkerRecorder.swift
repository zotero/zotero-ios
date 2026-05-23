//
//  DocumentWorkerRecorder.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 22/05/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import OrderedCollections

import RxSwift

final class DocumentWorkerRecorder {
    struct Record: Equatable, Identifiable {
        enum Status: Equatable {
            case queued
            case running
            case finished
            case failed
            case cancelled

            init?(kind: DocumentWorkerController.Update.Kind) {
                switch kind {
                case .queued:
                    self = .queued

                case .inProgress:
                    self = .running

                case .extractedData:
                    self = .finished

                case .failed:
                    self = .failed

                case .cancelled:
                    self = .cancelled
                }
            }

            var isTerminal: Bool {
                switch self {
                case .finished, .failed, .cancelled:
                    return true

                case .queued, .running:
                    return false
                }
            }
        }

        let id: String
        let workerId: UUID
        let work: DocumentWorkerController.Work
        let fileName: String
        let priority: DocumentWorkerController.Priority
        let runtime: DocumentWorkerController.HandlerRuntime
        let createdAt: Date
        var status: Status
        var startedAt: Date?
        var finishedAt: Date?
        var duration: CFTimeInterval?
    }

    private let accessQueue: DispatchQueue
    private let recordsSubject: BehaviorSubject<[Record]>
    private let disposeBag: DisposeBag
    private var activeRecordIdsByEventId: [String: String]
    private var attemptsByEventId: [String: Int]
    private var recordsById: OrderedDictionary<String, Record>

    var recordsObservable: Observable<[Record]> {
        return recordsSubject.asObservable()
    }

    var records: [Record] {
        accessQueue.sync {
            return Array(recordsById.values)
        }
    }

    init() {
        accessQueue = DispatchQueue(label: "org.zotero.DocumentWorkerRecorder.accessQueue")
        recordsSubject = BehaviorSubject(value: [])
        disposeBag = DisposeBag()
        activeRecordIdsByEventId = [:]
        attemptsByEventId = [:]
        recordsById = [:]
    }

    func bind(_ updates: Observable<DocumentWorkerController.Update>) {
        updates
            .subscribe(onNext: { [weak self] update in
                self?.process(update)
            })
            .disposed(by: disposeBag)
    }

    func clearFinishedWorkHistory() {
        accessQueue.async { [weak self] in
            guard let self else { return }
            let ids = recordsById.compactMap { $0.value.status.isTerminal ? $0.key : nil }
            for id in ids {
                recordsById.removeValue(forKey: id)
            }
            emitRecords()
        }
    }

    private func process(_ update: DocumentWorkerController.Update) {
        accessQueue.async { [weak self] in
            guard let self else { return }
            guard let workerId = update.workerId,
                  let fileName = update.fileName,
                  let priority = update.priority,
                  let runtime = update.runtime,
                  let status = Record.Status(kind: update.kind)
            else { return }

            let eventId = "\(workerId.uuidString):\(update.work.id)"
            if status == .queued || activeRecordIdsByEventId[eventId] == nil {
                activeRecordIdsByEventId[eventId] = createRecordId(for: eventId)
            }
            guard let recordId = activeRecordIdsByEventId[eventId] else { return }
            if var record = recordsById[recordId] {
                let original = record
                record.status = status
                if let startedAt = update.startedAt {
                    record.startedAt = startedAt
                }
                if status.isTerminal {
                    record.finishedAt = Date()
                    record.duration = update.duration
                    activeRecordIdsByEventId[eventId] = nil
                }
                guard record != original else { return }
                recordsById[recordId] = record
            } else {
                recordsById[recordId] = Record(
                    id: recordId,
                    workerId: workerId,
                    work: update.work,
                    fileName: fileName,
                    priority: priority,
                    runtime: runtime,
                    createdAt: Date(),
                    status: status,
                    startedAt: update.startedAt,
                    finishedAt: status.isTerminal ? Date() : nil,
                    duration: status.isTerminal ? update.duration : nil
                )
                if status.isTerminal {
                    activeRecordIdsByEventId[eventId] = nil
                }
            }
            emitRecords()
        }
    }

    private func createRecordId(for eventId: String) -> String {
        let attempt = attemptsByEventId[eventId, default: 0] + 1
        attemptsByEventId[eventId] = attempt
        return "\(eventId):\(attempt)"
    }

    private func emitRecords() {
        recordsSubject.on(.next(Array(recordsById.values)))
    }
}
