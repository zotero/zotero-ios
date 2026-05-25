//
//  DocumentWorkerRecorderView.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 23/05/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

import RxSwift

struct DocumentWorkerRecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DocumentWorkerRecorderViewModel

    init(recorder: DocumentWorkerRecorder) {
        _viewModel = StateObject(wrappedValue: DocumentWorkerRecorderViewModel(recorder: recorder))
    }

    var body: some View {
        NavigationStack {
            List {
                if viewModel.records.isEmpty {
                    Section {
                        Text("No document worker activity in this session.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(viewModel.records) { record in
                            RecordRow(record: record)
                        }
                    }
                }
            }
            .navigationTitle("Document Worker")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.done) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Clear Finished") {
                        viewModel.clearFinishedWorkHistory()
                    }
                    .disabled(!viewModel.hasTerminalRecords)
                }
            }
        }
    }
}

private final class DocumentWorkerRecorderViewModel: ObservableObject {
    @Published private(set) var records: [DocumentWorkerRecorder.Record]

    private let recorder: DocumentWorkerRecorder
    private let disposeBag: DisposeBag

    var hasTerminalRecords: Bool {
        return records.contains(where: { $0.status.isTerminal })
    }

    init(recorder: DocumentWorkerRecorder) {
        self.recorder = recorder
        records = recorder.records
        disposeBag = DisposeBag()

        recorder.recordsObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] records in
                self?.records = records
            })
            .disposed(by: disposeBag)
    }

    func clearFinishedWorkHistory() {
        recorder.clearFinishedWorkHistory()
    }
}

private struct RecordRow: View {
    let record: DocumentWorkerRecorder.Record

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.work.title)
                    .font(.headline)
                Spacer(minLength: 12)
                StatusText(status: record.status)
            }

            Text(record.fileName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    MetadataText(record.runtime.title)
                    MetadataText(record.priority.title)
                    if let duration = record.duration {
                        MetadataText("\(String(format: "%.3f", duration))s")
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    MetadataText(record.runtime.title)
                    MetadataText(record.priority.title)
                    if let duration = record.duration {
                        MetadataText("\(String(format: "%.3f", duration))s")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct StatusText: View {
    let status: DocumentWorkerRecorder.Record.Status

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
    }
}

private struct MetadataText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private extension DocumentWorkerController.Work {
    var title: String {
        switch self {
        case .recognizer:
            return "Recognizer"

        case .fullText:
            return "Full Text"

        case .structuredDocumentText:
            return "Structured Text"
        }
    }
}

private extension DocumentWorkerController.HandlerRuntime {
    var title: String {
        switch self {
        case .jsContext:
            return "JavaScriptCore"

        case .webView:
            return "WebView"
        }
    }
}

private extension DocumentWorkerController.Priority {
    var title: String {
        switch self {
        case .default:
            return "Normal"

        case .high:
            return "High"
        }
    }
}

private extension DocumentWorkerRecorder.Record.Status {
    var title: String {
        switch self {
        case .queued:
            return "Queued"

        case .running:
            return "Running"

        case .finished:
            return "Finished"

        case .failed:
            return "Failed"

        case .cancelled:
            return "Cancelled"
        }
    }

    var color: Color {
        switch self {
        case .queued:
            return .secondary

        case .running:
            return .blue

        case .finished:
            return .green

        case .failed:
            return .red

        case .cancelled:
            return .orange
        }
    }
}
