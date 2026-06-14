//
//  DocumentWorkerRecorderView.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 23/05/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI
import UIKit

import RxSwift

struct DocumentWorkerRecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DocumentWorkerRecorderViewModel

    init(documentWorkerController: DocumentWorkerController, recorder: DocumentWorkerRecorder) {
        _viewModel = StateObject(
            wrappedValue: DocumentWorkerRecorderViewModel(
                documentWorkerController: documentWorkerController,
                recorder: recorder
            )
        )
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
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if record.status == .finished, record.work.hasShareableCache {
                                        Button {
                                            viewModel.shareCache(for: record)
                                        } label: {
                                            Label("Share Cache", systemImage: "square.and.arrow.up")
                                        }
                                        .tint(.blue)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if !record.status.isTerminal {
                                        Button(role: .destructive) {
                                            viewModel.cancel(record)
                                        } label: {
                                            Label(L10n.cancel, systemImage: "xmark.circle")
                                        }
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Document Worker")
            .sheet(item: $viewModel.shareSheet) { shareSheet in
                ActivityViewController(activityItems: shareSheet.urls.map { $0 as Any })
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.done) {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Clear Cached Works", role: .destructive) {
                        viewModel.clearCachedWorks()
                    }

                    Button("Clear Finished") {
                        viewModel.clearFinishedWorkHistory()
                    }
                    .disabled(!viewModel.hasTerminalRecords)
                }
            }
        }
    }
}

private struct ShareSheet: Identifiable {
    let id = UUID()
    let urls: [URL]
}

private final class DocumentWorkerRecorderViewModel: ObservableObject {
    @Published private(set) var records: [DocumentWorkerRecorder.Record]
    @Published var shareSheet: ShareSheet?

    private let documentWorkerController: DocumentWorkerController
    private let recorder: DocumentWorkerRecorder
    private let disposeBag: DisposeBag

    var hasTerminalRecords: Bool {
        return records.contains(where: { $0.status.isTerminal })
    }

    init(documentWorkerController: DocumentWorkerController, recorder: DocumentWorkerRecorder) {
        self.documentWorkerController = documentWorkerController
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

    func clearCachedWorks() {
        documentWorkerController.clearCachedWorks()
    }

    func shareCache(for record: DocumentWorkerRecorder.Record) {
        documentWorkerController.cachedWorkFileURLs(for: record.work, fileURL: record.fileURL) { [weak self] urls in
            guard !urls.isEmpty else { return }
            self?.shareSheet = ShareSheet(urls: urls)
        }
    }

    func cancel(_ record: DocumentWorkerRecorder.Record) {
        guard !record.status.isTerminal else { return }
        documentWorkerController.cancelWork(record.work, workerId: record.workerId)
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
                    if let duration = record.durationText {
                        MetadataText(duration)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    MetadataText(record.runtime.title)
                    MetadataText(record.priority.title)
                    if let duration = record.durationText {
                        MetadataText(duration)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private extension DocumentWorkerRecorder.Record {
    var durationText: String? {
        guard let duration else { return nil }
        let text = "\(String(format: "%.3f", duration))s"
        return isCached ? "\(text) (cached)" : text
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

private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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

    var hasShareableCache: Bool {
        switch self {
        case .fullText, .structuredDocumentText:
            return true

        case .recognizer:
            return false
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
