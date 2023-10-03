//
//  HtmlEpubReaderActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 14.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

final class HtmlEpubReaderActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias Action = HtmlEpubReaderAction
    typealias State = HtmlEpubReaderState

    unowned let dbStorage: DbStorage
    unowned let schemaController: SchemaController
    let backgroundQueue: DispatchQueue

    init(dbStorage: DbStorage, schemaController: SchemaController) {
        self.dbStorage = dbStorage
        self.schemaController = schemaController
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

        case .selectAnnotations(let params):
            selectAnnotations(params: params, in: viewModel)
        }
    }

    private func selectAnnotations(params: [String: Any], in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
    }

    private func saveAnnotations(params: [String: Any], in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        guard let rawAnnotations = params["annotations"] as? [[String: Any]], !rawAnnotations.isEmpty else {
            DDLogError("HtmlEpubReaderActionHandler: annotations missing or empty - \(params["annotations"] ?? [])")
            return
        }

        let annotations = parse(annotations: rawAnnotations, author: viewModel.state.username, isAuthor: true)

        guard annotations.isEmpty else {
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
                      let dateCreated = (data["dateCreated"] as? String).flatMap({ DateFormatter.iso8601.date(from: $0) }),
                      let dateModified = (data["dateModified"] as? String).flatMap({ DateFormatter.iso8601.date(from: $0) }),
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
            let data = try Data(contentsOf: viewModel.state.url)
            let jsArrayData = try JSONSerialization.data(withJSONObject: [UInt8](data))
            guard let jsArrayString = String(data: jsArrayData, encoding: .utf8) else {
                DDLogError("HtmlEpubReaderActionHandler: can't convert data to string")
                return
            }
            let annotations = loadAnnotationsJson(in: viewModel)
            let documentData = HtmlEpubReaderState.DocumentData(buffer: jsArrayString, annotationsJson: annotations)
            self.update(viewModel: viewModel) { state in
                state.documentData = documentData
            }
        } catch let error {
            DDLogError("HtmlEpubReaderActionHandler: could not load document - \(error)")
        }
    }

    private func loadAnnotationsJson(in viewModel: ViewModel<HtmlEpubReaderActionHandler>) -> String {
        do {
            let request = ReadAnnotationsDbRequest(attachmentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier)
            let items = try self.dbStorage.perform(request: request, on: .main)
            var jsons: [[String: Any]] = []

            for item in items {
                let tags = Array(item.tags.map({ typedTag in
                    let color: String? = (typedTag.tag?.color ?? "").isEmpty ? nil : typedTag.tag?.color
                    return ["name": typedTag.tag?.name ?? "", "color": color]
                }))
                var data: [String: Any] = [
                    "id": item.key,
                    "dateCreated": DateFormatter.iso8601.string(from: item.dateAdded),
                    "dateModified": DateFormatter.iso8601.string(from: item.dateModified),
                    "authorName": item.createdBy?.username ?? "",
                    "tags": tags
                ]
                var position: [String: Any] = [:]
                for field in item.fields {
                    switch (field.key, field.baseKey) {
                    case (FieldKeys.Item.Annotation.Position.htmlEpubType, FieldKeys.Item.Annotation.position):
                        position[FieldKeys.Item.Annotation.Position.htmlEpubType] = field.value

                    case (FieldKeys.Item.Annotation.Position.htmlEpubValue, FieldKeys.Item.Annotation.position):
                        position[FieldKeys.Item.Annotation.Position.htmlEpubValue] = field.value

                    case (FieldKeys.Item.Annotation.type, nil):
                        data["type"] = field.value

                    case (FieldKeys.Item.Annotation.text, nil):
                        data["text"] = field.value

                    case (FieldKeys.Item.Annotation.sortIndex, nil):
                        data["sortIndex"] = field.value

                    case (FieldKeys.Item.Annotation.pageLabel, nil):
                        data["pageLabel"] = field.value

                    case (FieldKeys.Item.Annotation.comment, nil):
                        data["comment"] = field.value

                    case (FieldKeys.Item.Annotation.color, nil):
                        data["color"] = field.value

                    default:
                        data[field.key] = field.value
                    }
                }
                data["position"] = position
                jsons.append(data)
            }

            let jsonData = try JSONSerialization.data(withJSONObject: jsons)

            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                DDLogError("HtmlEpubReaderActionHandler: can't convert json data to string")
                return "[]"
            }

            return jsonString
        } catch let error {
            DDLogError("HtmlEpubReaderActionHandler: can't load annotations - \(error)")
            return "[]"
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
