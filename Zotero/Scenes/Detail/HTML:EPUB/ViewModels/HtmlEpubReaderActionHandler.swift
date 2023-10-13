//
//  HtmlEpubReaderActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 14.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift

final class HtmlEpubReaderActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias Action = HtmlEpubReaderAction
    typealias State = HtmlEpubReaderState

    unowned let dbStorage: DbStorage
    private unowned let schemaController: SchemaController
    private unowned let htmlAttributedStringConverter: HtmlAttributedStringConverter
    let backgroundQueue: DispatchQueue

    init(dbStorage: DbStorage, schemaController: SchemaController, htmlAttributedStringConverter: HtmlAttributedStringConverter) {
        self.dbStorage = dbStorage
        self.schemaController = schemaController
        self.htmlAttributedStringConverter = htmlAttributedStringConverter
        self.backgroundQueue = DispatchQueue(label: "org.zotero.Zotero.HtmlEpubReaderActionHandler.queue", qos: .userInteractive)
    }

    func process(action: HtmlEpubReaderAction, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        switch action {
        case .toggleTool(let tool):
            toggle(tool: tool, in: viewModel)

        case .loadDocument:
            load(in: viewModel)

        case .saveAnnotations(let params):
            saveAnnotations(params: params, in: viewModel)

        case .selectAnnotation(let key):
            select(key: key, didSelectInDocument: false, in: viewModel)

        case .selectAnnotationFromDocument(let params):
            guard let key = (params["ids"] as? [String])?.first else { return }
            select(key: key, didSelectInDocument: true, in: viewModel)

        case .deselectSelectedAnnotation:
            select(key: nil, didSelectInDocument: false, in: viewModel)

        case .parseAndCacheComment(key: let key, comment: let comment):
            self.update(viewModel: viewModel, notifyListeners: false) { state in
                state.comments[key] = self.htmlAttributedStringConverter.convert(text: comment, baseAttributes: [.font: viewModel.state.commentFont])
            }
        }
    }

    private func select(key: String?, didSelectInDocument: Bool, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        self.update(viewModel: viewModel) { state in
            self._select(key: key, didSelectInDocument: didSelectInDocument, state: &state)
        }
    }

    private func _select(key: String?, didSelectInDocument: Bool, state: inout HtmlEpubReaderState) {
        guard key != state.selectedAnnotationKey else { return }

        if let existing = state.selectedAnnotationKey {
            add(updatedAnnotationKey: existing, state: &state)

            if state.selectedAnnotationCommentActive {
                state.selectedAnnotationCommentActive = false
                state.changes.insert(.activeComment)
            }
        }

        state.changes.insert(.selection)

        guard let key = key else {
            state.selectedAnnotationKey = nil
            return
        }

        state.selectedAnnotationKey = key

        if !didSelectInDocument {
//            if let boundingBoxConverter = self.delegate, let annotation = state.annotation(for: key) {
//                state.focusDocumentLocation = (annotation.page, annotation.boundingBox(boundingBoxConverter: boundingBoxConverter))
//            }
        } else {
            state.focusSidebarKey = key
        }

        add(updatedAnnotationKey: key, state: &state)

        func add(updatedAnnotationKey key: String, state: inout HtmlEpubReaderState) {
            if state.annotations.contains(where: { $0.key == key }) {
                var updatedAnnotationKeys = state.updatedAnnotationKeys ?? []
                updatedAnnotationKeys.append(key)
                state.updatedAnnotationKeys = updatedAnnotationKeys
            }
        }
    }

    private func saveAnnotations(params: [String: Any], in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        guard let rawAnnotations = params["annotations"] as? [[String: Any]], !rawAnnotations.isEmpty else {
            DDLogError("HtmlEpubReaderActionHandler: annotations missing or empty - \(params["annotations"] ?? [])")
            return
        }

        let annotations = parse(annotations: rawAnnotations, author: viewModel.state.username, isAuthor: true)

        guard !annotations.isEmpty else {
            DDLogError("HtmlEpubReaderActionHandler: could not parse annotations")
            return
        }

        let request = CreateHtmlEpubAnnotationsDbRequest(
            attachmentKey: viewModel.state.key,
            libraryId: viewModel.state.library.identifier,
            annotations: annotations,
            userId: viewModel.state.userId,
            schemaController: schemaController
        )
        self.perform(request: request) { [weak viewModel] error in
            guard let error, let viewModel else { return }

            DDLogError("HtmlEpubReaderActionHandler: could not store annotations - \(error)")

            self.update(viewModel: viewModel) { state in
                state.error = .cantAddAnnotations
            }
        }

        func parse(annotations: [[String: Any]], author: String, isAuthor: Bool) -> [HtmlEpubAnnotation] {
            return annotations.compactMap { data -> HtmlEpubAnnotation? in
                guard let id = data["id"] as? String,
                      let dateCreated = (data["dateCreated"] as? String).flatMap({ DateFormatter.iso8601WithFractionalSeconds.date(from: $0) }),
                      let dateModified = (data["dateModified"] as? String).flatMap({ DateFormatter.iso8601WithFractionalSeconds.date(from: $0) }),
                      let color = data["color"] as? String,
                      let comment = data["comment"] as? String,
                      let pageLabel = data["pageLabel"] as? String,
                      let position = data["position"] as? [String: Any],
                      let sortIndex = data["sortIndex"] as? String,
                      let text = data["text"] as? String,
                      let type = (data["type"] as? String).flatMap(AnnotationType.init),
                      let rawTags = data["tags"] as? [[String: Any]]
                else { return nil }
                let tags = rawTags.compactMap({ data -> Tag? in
                    guard let name = data["name"] as? String,
                          let color = data["color"] as? String
                    else { return nil }
                    return Tag(name: name, color: color)
                })
                return HtmlEpubAnnotation(
                    key: id,
                    type: type,
                    pageLabel: pageLabel,
                    position: position,
                    author: author,
                    isAuthor: isAuthor,
                    color: color,
                    comment: comment,
                    text: text,
                    sortIndex: sortIndex,
                    dateModified: dateModified,
                    dateCreated: dateCreated,
                    tags: tags
                )
            }
        }
    }

    private func load(in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        do {
//            try self.dbStorage.perform(request: DeleteObjectsDbRequest<RItem>(keys: ["LDAC2BLR"], libraryId: viewModel.state.library.identifier), on: .main)
            let data = try Data(contentsOf: viewModel.state.url)
            let jsArrayData = try JSONSerialization.data(withJSONObject: [UInt8](data))
            guard let jsArrayString = String(data: jsArrayData, encoding: .utf8) else {
                DDLogError("HtmlEpubReaderActionHandler: can't convert data to string")
                return
            }
            let (annotations, json) = loadAnnotationsAndJson(in: viewModel)
            let documentData = HtmlEpubReaderState.DocumentData(buffer: jsArrayString, annotationsJson: json)
            self.update(viewModel: viewModel) { state in
                state.annotations = annotations
                state.documentData = documentData
                state.changes = .annotations
            }
        } catch let error {
            DDLogError("HtmlEpubReaderActionHandler: could not load document - \(error)")
        }
    }

    private func loadAnnotationsAndJson(in viewModel: ViewModel<HtmlEpubReaderActionHandler>) -> ([HtmlEpubAnnotation], String) {
        do {
            let request = ReadAnnotationsDbRequest(attachmentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier)
            let items = try self.dbStorage.perform(request: request, on: .main)
            var annotations: [HtmlEpubAnnotation] = []
            var jsons: [[String: Any]] = []

            for item in items {
                let tags = Array(item.tags.map({ typedTag in
                    let color: String? = (typedTag.tag?.color ?? "").isEmpty ? nil : typedTag.tag?.color
                    return Tag(name: typedTag.tag?.name ?? "", color: color ?? "")
                }))

                var type: AnnotationType?
                var position: [String: Any] = [:]
                var text: String?
                var sortIndex: String?
                var pageLabel: String?
                var comment: String?
                var color: String?
                var unknown: [String: String] = [:]

                for field in item.fields {
                    switch (field.key, field.baseKey) {
                    case (FieldKeys.Item.Annotation.Position.htmlEpubType, FieldKeys.Item.Annotation.position):
                        position[FieldKeys.Item.Annotation.Position.htmlEpubType] = field.value

                    case (FieldKeys.Item.Annotation.Position.htmlEpubValue, FieldKeys.Item.Annotation.position):
                        position[FieldKeys.Item.Annotation.Position.htmlEpubValue] = field.value

                    case (FieldKeys.Item.Annotation.type, nil):
                        type = AnnotationType(rawValue: field.value)

                    case (FieldKeys.Item.Annotation.text, nil):
                        text = field.value

                    case (FieldKeys.Item.Annotation.sortIndex, nil):
                        sortIndex = field.value

                    case (FieldKeys.Item.Annotation.pageLabel, nil):
                        pageLabel = field.value

                    case (FieldKeys.Item.Annotation.comment, nil):
                        comment = field.value

                    case (FieldKeys.Item.Annotation.color, nil):
                        color = field.value

                    default:
                        unknown[field.key] = field.value
                    }
                }

                guard let type, let sortIndex, !position.isEmpty else { continue }

                jsons.append(
                    [
                        "id": item.key,
                        "dateCreated": DateFormatter.iso8601WithFractionalSeconds.string(from: item.dateAdded),
                        "dateModified": DateFormatter.iso8601WithFractionalSeconds.string(from: item.dateModified),
                        "authorName": item.createdBy?.username ?? "",
                        "type": type.rawValue,
                        "text": text ?? "",
                        "sortIndex": sortIndex,
                        "pageLabel": pageLabel ?? "",
                        "comment": comment ?? "",
                        "color": color ?? "",
                        "position": position,
                        "tags": tags.map({ ["name": $0.name, "color": $0.color] })
                    ]
                )
                annotations.append(
                    HtmlEpubAnnotation(
                        key: item.key,
                        type: type,
                        pageLabel: pageLabel ?? "",
                        position: position,
                        author: item.createdBy?.username ?? "",
                        isAuthor: true,
                        color: color ?? "",
                        comment: comment ?? "",
                        text: text,
                        sortIndex: sortIndex,
                        dateModified: item.dateModified,
                        dateCreated: item.dateAdded,
                        tags: tags
                    )
                )
            }

            let jsonData = try JSONSerialization.data(withJSONObject: jsons)

            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                DDLogError("HtmlEpubReaderActionHandler: can't convert json data to string")
                return ([], "[]")
            }

            return (annotations, jsonString)
        } catch let error {
            DDLogError("HtmlEpubReaderActionHandler: can't load annotations - \(error)")
            return ([], "[]")
        }
    }

    private func toggle(tool: AnnotationTool, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        self.update(viewModel: viewModel) { state in
            if state.activeTool == tool {
                state.activeTool = nil
            } else {
                state.activeTool = tool
            }
            state.changes = .activeTool
        }
    }
}
